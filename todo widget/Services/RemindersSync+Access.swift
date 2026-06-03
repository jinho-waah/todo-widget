import EventKit
import OSLog

enum AccessResolution {
    case granted
    case blocked
}

extension RemindersSync {
    func resolveAccess(requestIfNeeded: Bool) async -> AccessResolution {
        let authStatus = eventStore.currentAuthorizationStatus()
        remindersLog.info("authStatus before request → \(authStatus.rawValue, privacy: .public)")

        switch authStatus {
        case .fullAccess:
            accessConfirmed = true
            eventStore.markAccessGranted()
            status = .granted
            lastRequestError = nil
            return .granted

        case .denied, .restricted:
            // 명시적 거부/제한만 권한을 깎아내린다 (System Settings 에서 끈 경우).
            accessConfirmed = false
            eventStore.markAccessDenied()
            status = .denied
            remindersLog.warning("Reminders access denied/restricted — enable in System Settings → Privacy → Reminders.")
            return .blocked

        case .notDetermined, .writeOnly:
            // 디버그 빌드 TCC 버그: grant 후에도 .notDetermined 로 보고됨. 이번 세션에서 이미
            // 접근을 확인했다면 풀린 것으로 보지 않고 granted 유지 → 배너 깜빡임 방지.
            if accessConfirmed {
                eventStore.markAccessGranted()
                status = .granted
                return .granted
            }
            eventStore.markAccessDenied()
            status = .notDetermined
            guard requestIfNeeded else {
                remindersLog.info("Reminders access not determined — waiting for explicit user request.")
                return .blocked
            }
            return await requestAccess()

        case .authorized:
            return await requestAccess()

        @unknown default:
            return await requestAccess()
        }
    }

    func requestAccess() async -> AccessResolution {
        guard !isRequestingAccess else { return .blocked }
        isRequestingAccess = true
        status = .requesting
        lastRequestError = nil
        defer { isRequestingAccess = false }

        do {
            let granted = try await eventStore.requestFullAccess()
            let afterRequest = eventStore.currentAuthorizationStatus()
            remindersLog.info("requestFullAccessToReminders → \(granted, privacy: .public), authStatus after request → \(afterRequest.rawValue, privacy: .public)")

            guard granted else {
                eventStore.markAccessDenied()
                status = (afterRequest == .denied || afterRequest == .restricted) ? .denied : .requestFailed
                lastRequestError = "요청이 완료됐지만 권한이 부여되지 않았습니다."
                remindersLog.warning("requestFullAccessToReminders returned false, authStatus after request → \(afterRequest.rawValue, privacy: .public)")
                return .blocked
            }

            accessConfirmed = true
            eventStore.markAccessGranted()
            status = .granted
            lastRequestError = nil
            resetEventStoreAfterPermissionChange()
            eventStore.markAccessGranted()
            return .granted
        } catch {
            eventStore.markAccessDenied()
            status = .requestFailed
            lastRequestError = String(describing: error)
            remindersLog.error("requestFullAccessToReminders threw: \(String(describing: error), privacy: .public)")
            return .blocked
        }
    }
}
