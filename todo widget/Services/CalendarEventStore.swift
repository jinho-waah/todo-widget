import AppKit
import EventKit
import OSLog
import SwiftUI

let calendarLog = Logger(subsystem: "todo-widget", category: "CalendarService")

// macOS 캘린더(EKEvent) 접근 래퍼. RemindersEventStore 의 이벤트 버전.
// EventKit 의 `.event` 엔타이틀먼트(미리 알림과 별개 권한)를 사용한다.
@MainActor
final class CalendarEventStore {
    private var store = EKEventStore()

    private(set) var hasAccess = false

    func currentAuthorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    func markAccessGranted() { hasAccess = true }
    func markAccessDenied() { hasAccess = false }

    func requestFullAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: granted)
            }
        }
    }

    /// EKEventStore 는 생성 시점의 권한 상태를 캐시한다. notDetermined→granted 전환 후
    /// store 를 새로 만들지 않으면 이후 fetch/save 가 조용히 빈 결과를 낸다.
    func recreateStore() {
        store = EKEventStore()
    }

    // MARK: Read

    func fetchEvents(from start: Date, to end: Date) -> [CalendarEvent] {
        guard hasAccess else { return [] }
        // 구글 계정 캘린더는 제외 (단, 공휴일 캘린더는 소스와 무관하게 항상 포함 — 휴일 표시용).
        let calendars = store.calendars(for: .event)
            .filter { !Self.isGoogleCalendar($0) || Self.isHolidayCalendar($0) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .map(Self.snapshot(from:))
            .sorted { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    /// 구글 계정에 속한 캘린더인지. 소스 타이틀이 google/gmail 을 포함하면 구글로 본다
    /// (macOS 는 구글 계정 소스 타이틀을 보통 계정 이메일 또는 "Google" 로 둔다).
    static func isGoogleCalendar(_ calendar: EKCalendar) -> Bool {
        let title = calendar.source.title.lowercased()
        return title.contains("google") || title.contains("gmail")
    }

    /// "대한민국 공휴일" 같은 공휴일 캘린더인지. 휴일 날짜색 표시용으로만 쓰고 아젠다/점에서는 뺀다.
    static func isHolidayCalendar(_ calendar: EKCalendar) -> Bool {
        let title = calendar.title.lowercased()
        return title.contains("공휴일") || title.contains("holiday")
    }

    func writableCalendars() -> [WritableCalendar] {
        guard hasAccess else { return [] }
        return store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map { WritableCalendar(id: $0.calendarIdentifier, title: $0.title, color: Color(cgColor: $0.cgColor)) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var defaultCalendarID: String? {
        store.defaultCalendarForNewEvents?.calendarIdentifier
    }

    // MARK: Write

    /// 새 일정 생성. 성공 시 생성된 스냅샷을 반환한다. (Claude 에이전트가 호출할 진입점)
    @discardableResult
    func createEvent(
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        calendarID: String?,
        notes: String?,
        location: String?
    ) -> CalendarEvent? {
        guard hasAccess, let calendar = resolvedCalendar(forID: calendarID) else {
            calendarLog.warning("createEvent skipped — no access or no writable calendar")
            return nil
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        apply(title: title, start: start, end: end, isAllDay: isAllDay, notes: notes, location: location, to: event)

        do {
            try store.save(event, span: .thisEvent, commit: true)
            calendarLog.info("createEvent OK — '\(title, privacy: .public)'")
            return Self.snapshot(from: event)
        } catch {
            calendarLog.error("createEvent failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// 기존 일정 편집. 캘린더 이동(calendarID 변경)도 처리한다.
    @discardableResult
    func update(
        eventID: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        calendarID: String?,
        notes: String?,
        location: String?
    ) -> CalendarEvent? {
        guard hasAccess, let event = store.event(withIdentifier: eventID) else {
            calendarLog.warning("update skipped — event not found")
            return nil
        }
        if let calendarID, event.calendar.calendarIdentifier != calendarID,
           let target = resolvedCalendar(forID: calendarID) {
            event.calendar = target
        }
        apply(title: title, start: start, end: end, isAllDay: isAllDay, notes: notes, location: location, to: event)

        do {
            try store.save(event, span: .thisEvent, commit: true)
            calendarLog.info("update OK — '\(title, privacy: .public)'")
            return Self.snapshot(from: event)
        } catch {
            calendarLog.error("update failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func delete(eventID: String) {
        guard hasAccess, let event = store.event(withIdentifier: eventID) else { return }
        do {
            try store.remove(event, span: .thisEvent, commit: true)
            calendarLog.info("delete OK")
        } catch {
            calendarLog.error("delete failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Helpers

    private func apply(
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        notes: String?,
        location: String?,
        to event: EKEvent
    ) {
        event.title = title
        event.startDate = start
        event.endDate = max(end, start)
        event.isAllDay = isAllDay
        event.notes = notes
        event.location = location
    }

    private func resolvedCalendar(forID calendarID: String?) -> EKCalendar? {
        if let calendarID,
           let calendar = store.calendars(for: .event)
            .first(where: { $0.calendarIdentifier == calendarID && $0.allowsContentModifications }) {
            return calendar
        }
        if let def = store.defaultCalendarForNewEvents, def.allowsContentModifications {
            return def
        }
        return store.calendars(for: .event).first(where: \.allowsContentModifications)
    }

    private static func snapshot(from event: EKEvent) -> CalendarEvent {
        CalendarEvent(
            eventID: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "(제목 없음)",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            color: Color(cgColor: event.calendar.cgColor),
            calendarID: event.calendar.calendarIdentifier,
            location: event.location,
            notes: event.notes,
            isHoliday: isHolidayCalendar(event.calendar)
        )
    }
}
