import AppKit
import EventKit
import OSLog
import SwiftUI

@MainActor
final class RemindersEventStore {
    private var store = EKEventStore()
    private var defaultCalendar: EKCalendar?
    private let listName = "todo widget"

    private(set) var hasAccess = false

    var defaultListID: String? {
        defaultCalendar?.calendarIdentifier
    }

    var calendarCount: Int {
        store.calendars(for: .reminder).count
    }

    func currentAuthorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    func markAccessGranted() {
        hasAccess = true
    }

    func markAccessDenied() {
        hasAccess = false
    }

    func requestFullAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: granted)
            }
        }
    }

    func recreateStore() {
        defaultCalendar = nil
        store = EKEventStore()
    }

    func ensureDefaultCalendar() throws {
        guard defaultCalendar == nil else { return }
        defaultCalendar = try loadOrCreateDefaultCalendar()
        remindersLog.info("ensureCalendar → list '\(self.listName, privacy: .public)' id=\(self.defaultCalendar?.calendarIdentifier ?? "nil", privacy: .public)")
    }

    func availableLists() -> [ReminderList] {
        guard hasAccess else { return [] }
        return store.calendars(for: .reminder)
            .filter(\.allowsContentModifications)
            .map { calendar in
                ReminderList(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    color: Color(cgColor: calendar.cgColor)
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func createList(named title: String, color: NSColor) async -> String? {
        guard hasAccess else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let existing = store.calendars(for: .reminder).first(where: {
            $0.title.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
                && $0.allowsContentModifications
        }) {
            return existing.calendarIdentifier
        }

        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = trimmed
        calendar.source = preferredReminderSource()
        calendar.cgColor = color.cgColor

        do {
            try store.saveCalendar(calendar, commit: true)
            remindersLog.info("createList OK — '\(trimmed, privacy: .public)'")
            return calendar.calendarIdentifier
        } catch {
            remindersLog.error("saveCalendar failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func color(forListID listID: String?) -> Color? {
        guard hasAccess else { return nil }
        let calendars = store.calendars(for: .reminder)
        if let listID,
           let calendar = calendars.first(where: { $0.calendarIdentifier == listID }) {
            return Color(cgColor: calendar.cgColor)
        }
        if let defaultCalendar {
            return Color(cgColor: defaultCalendar.cgColor)
        }
        return nil
    }

    func fetchAllReminders() async -> [EKReminder] {
        guard hasAccess else { return [] }
        store.reset()
        let predicate = store.predicateForReminders(in: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { result in
                continuation.resume(returning: result ?? [])
            }
        }
    }

    func belongsToDefaultCalendar(_ reminder: EKReminder) -> Bool {
        guard let defaultCalendar else { return false }
        return reminder.calendar.calendarIdentifier == defaultCalendar.calendarIdentifier
    }

    func save(_ todo: Todo) throws {
        guard let targetCalendar = resolvedCalendar(for: todo) else {
            throw RemindersEventStoreError.missingCalendar
        }

        let reminder: EKReminder
        if let reminderID = todo.reminderID,
           let existing = store.calendarItem(withIdentifier: reminderID) as? EKReminder {
            reminder = existing
            if reminder.calendar.calendarIdentifier != targetCalendar.calendarIdentifier {
                reminder.calendar = targetCalendar
            }
        } else {
            reminder = EKReminder(eventStore: store)
            reminder.calendar = targetCalendar
        }

        reminder.title = todo.title
        reminder.notes = todo.todoDescription
        reminder.isCompleted = todo.isCompleted
        reminder.dueDateComponents = todo.dueDate.map {
            Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0)
        }

        try store.save(reminder, commit: true)
        todo.reminderID = reminder.calendarItemIdentifier
        todo.reminderListID = reminder.calendar.calendarIdentifier
        remindersLog.info("push OK — '\(todo.title, privacy: .public)' → list='\(targetCalendar.title, privacy: .public)'")
    }

    func delete(reminderID: String?) {
        guard hasAccess,
              let reminderID,
              let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            return
        }
        try? store.remove(reminder, commit: true)
    }

    private func loadOrCreateDefaultCalendar() throws -> EKCalendar {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == listName }) {
            return existing
        }

        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = listName
        calendar.source = preferredReminderSource()
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    private func preferredReminderSource() -> EKSource? {
        store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV })
            ?? store.sources.first(where: { $0.sourceType == .local })
            ?? store.sources.first
    }

    private func resolvedCalendar(for todo: Todo) -> EKCalendar? {
        if let listID = todo.reminderListID,
           let calendar = store.calendars(for: .reminder)
            .first(where: { $0.calendarIdentifier == listID }) {
            return calendar
        }
        return defaultCalendar
    }
}

enum RemindersEventStoreError: Error {
    case missingCalendar
}
