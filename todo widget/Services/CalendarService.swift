import AppKit
import EventKit
import OSLog
import SwiftUI

// macOS 캘린더(EKEvent) 읽기/쓰기 facade. RemindersSync 의 캘린더 버전.
//
// 표시 중인 월을 중심으로 일정 window 를 fetch 해 캐시하고, 그리드 점 표시와
// 아젠다 목록을 위한 조회 헬퍼를 제공한다. 생성/편집/삭제는 CalendarEventStore 에 위임.
//
// `createEvent(...)` 는 향후 Claude 에이전트("메시지 → 일정")가 그대로 호출할 진입점이다.
@MainActor
@Observable
final class CalendarService {
    @ObservationIgnored static let shared = CalendarService()

    @ObservationIgnored private let store = CalendarEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var isRequestingAccess = false

    @ObservationIgnored private var anchorMonth: Date?

    /// 이번 세션에서 접근이 확인됐는지. 디버그(ad-hoc 서명) 빌드의 TCC 버그로 grant 후에도
    /// `authorizationStatus` 가 `.notDetermined` 로 보고될 때, 일시적 읽기로 권한이 풀려
    /// 배너가 다시 뜨는 것을 막는다. 세션 한정(새 실행마다 false). RemindersSync 와 동일.
    @ObservationIgnored private var accessConfirmed = false

    var status: CalendarAccessStatus = .unknown
    private(set) var events: [CalendarEvent] = []

    /// 아젠다("선택일부터 다가오는 일정")의 기본 horizon.
    nonisolated static let agendaHorizonDays = 90

    private init() {}

    // MARK: Lifecycle

    func start(month: Date) {
        Task { await bootstrap(month: month, requestIfNeeded: false) }
    }

    func refresh() async {
        guard !isRequestingAccess, let anchorMonth else { return }
        await bootstrap(month: anchorMonth, requestIfNeeded: false)
    }

    func requestAccessFromUser(month: Date) async {
        await bootstrap(month: month, requestIfNeeded: true)
    }

    /// 표시 월이 바뀔 때 호출 — window 를 갱신하고 다시 fetch 한다.
    func setMonth(_ month: Date) async {
        anchorMonth = month
        guard status == .granted else { return }
        reloadWindow(around: month)
    }

    private func bootstrap(month: Date, requestIfNeeded: Bool) async {
        anchorMonth = month
        switch await resolveAccess(requestIfNeeded: requestIfNeeded) {
        case .granted:
            break
        case .blocked:
            events = []
            return
        }
        installStoreChangeObserverIfNeeded()
        reloadWindow(around: month)
    }

    private func reloadWindow(around month: Date) {
        let cal = Calendar.current
        let monthStart = cal.startOfMonth(for: month)
        // 그리드 leading 흘림(최대 6일) + 아젠다 horizon 을 모두 덮는 넉넉한 범위.
        let start = cal.date(byAdding: .day, value: -7, to: monthStart) ?? monthStart
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let end = cal.date(byAdding: .day, value: Self.agendaHorizonDays + 7, to: monthEnd) ?? monthEnd
        events = store.fetchEvents(from: start, to: end)
        calendarLog.info("calendar window \(self.events.count) events")
    }

    // MARK: Access

    private func resolveAccess(requestIfNeeded: Bool) async -> AccessResolution {
        switch store.currentAuthorizationStatus() {
        case .fullAccess, .authorized:
            accessConfirmed = true
            store.markAccessGranted()
            status = .granted
            return .granted
        case .denied, .restricted:
            accessConfirmed = false
            store.markAccessDenied()
            status = .denied
            return .blocked
        case .notDetermined, .writeOnly:
            // 디버그 빌드 TCC 버그: grant 후에도 .notDetermined 보고. 세션 내 확인됐으면 유지.
            if accessConfirmed {
                store.markAccessGranted()
                status = .granted
                return .granted
            }
            store.markAccessDenied()
            status = .notDetermined
            guard requestIfNeeded else { return .blocked }
            return await requestAccess()
        @unknown default:
            return await requestAccess()
        }
    }

    private func requestAccess() async -> AccessResolution {
        guard !isRequestingAccess else { return .blocked }
        isRequestingAccess = true
        status = .requesting
        defer { isRequestingAccess = false }

        do {
            let granted = try await store.requestFullAccess()
            guard granted else {
                store.markAccessDenied()
                let after = store.currentAuthorizationStatus()
                status = (after == .denied || after == .restricted) ? .denied : .requestFailed
                return .blocked
            }
            // 권한 전환 후 캐시된 store 를 새로 만들지 않으면 fetch 가 빈 결과를 낸다.
            store.recreateStore()
            accessConfirmed = true
            store.markAccessGranted()
            status = .granted
            return .granted
        } catch {
            store.markAccessDenied()
            status = .requestFailed
            calendarLog.error("event access request threw: \(String(describing: error), privacy: .public)")
            return .blocked
        }
    }

    private func installStoreChangeObserverIfNeeded() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    // MARK: Queries

    /// 특정 날짜에 걸치는 일정 (timed/all-day 모두 day 구간과 교집합으로 판정). 공휴일 제외.
    func events(on day: Date) -> [CalendarEvent] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return events.filter { !$0.isHoliday && $0.start < dayEnd && $0.end > dayStart }
    }

    /// 선택일부터 horizon 일까지 다가오는 일정 (시작 오름차순). 공휴일 제외.
    func upcomingEvents(from day: Date, days: Int = agendaHorizonDays) -> [CalendarEvent] {
        let cal = Calendar.current
        let from = cal.startOfDay(for: day)
        guard let to = cal.date(byAdding: .day, value: days, to: from) else { return [] }
        return events
            .filter { !$0.isHoliday && $0.end > from && $0.start < to }
            .sorted { $0.start < $1.start }
    }

    /// 해당 날짜가 공휴일인지 (공휴일 캘린더 이벤트가 그 날에 걸치면 true). 날짜 셀 휴일색 표시용.
    func isHoliday(on day: Date) -> Bool {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        return events.contains { $0.isHoliday && $0.start < dayEnd && $0.end > dayStart }
    }

    /// 그리드 점 표시용 — 표시 월의 각 날짜(startOfDay)에 걸치는 일정 색상(중복 제거, 최대 3).
    func eventColors(forDay day: Date) -> [Color] {
        var seen: [Color] = []
        for event in events(on: day) where !seen.contains(event.color) {
            seen.append(event.color)
            if seen.count == 3 { break }
        }
        return seen
    }

    // MARK: Mutations (Claude 에이전트 호출 진입점)

    @discardableResult
    func createEvent(
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        calendarID: String?,
        notes: String? = nil,
        location: String? = nil
    ) -> CalendarEvent? {
        let created = store.createEvent(
            title: title, start: start, end: end, isAllDay: isAllDay,
            calendarID: calendarID, notes: notes, location: location
        )
        if let anchorMonth { reloadWindow(around: anchorMonth) }
        return created
    }

    @discardableResult
    func update(
        eventID: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        calendarID: String?,
        notes: String? = nil,
        location: String? = nil
    ) -> CalendarEvent? {
        let updated = store.update(
            eventID: eventID, title: title, start: start, end: end, isAllDay: isAllDay,
            calendarID: calendarID, notes: notes, location: location
        )
        if let anchorMonth { reloadWindow(around: anchorMonth) }
        return updated
    }

    func delete(eventID: String) {
        store.delete(eventID: eventID)
        if let anchorMonth { reloadWindow(around: anchorMonth) }
    }

    func writableCalendars() -> [WritableCalendar] {
        store.writableCalendars()
    }

    var defaultCalendarID: String? {
        store.defaultCalendarID
    }
}
