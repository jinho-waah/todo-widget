import Foundation
import EventKit
import SwiftData
import AppKit

// MARK: - RemindersSync
// 로컬 SwiftData (Todo) ↔ macOS 미리 알림(EKReminder) 양방향 동기화.
//
// 매핑:
//   Todo.title           ↔ EKReminder.title
//   Todo.todoDescription ↔ EKReminder.notes
//   Todo.dueDate         ↔ EKReminder.dueDateComponents
//   Todo.isCompleted     ↔ EKReminder.isCompleted
//   Todo.reminderID      ↔ EKReminder.calendarItemIdentifier   (identity)
//
// SubTodo, Todo.order 는 sync 대상 아님 (Reminders API 가 sub-task / 순서를
// 안정적으로 노출하지 않음 → 로컬-only 로 유지).
//
// 모든 reminder 는 전용 list "todo widget" 에 저장되며, 첫 launch 시 자동 생성.

@MainActor
final class RemindersSync {
    static let shared = RemindersSync()

    private let store = EKEventStore()
    private let listName = "todo widget"

    private weak var modelContext: ModelContext?
    private var calendar: EKCalendar?
    private var hasAccess = false
    private var observer: NSObjectProtocol?
    /// bootstrap 진입 가드. `start(with:)` 가 view re-creation 등으로 여러 번 호출돼도
    /// observer / 권한 요청이 중복으로 일어나지 않도록 한다.
    private var didStart = false

    /// pull 중에 로컬을 변경할 때 잠깐 set → 변경 site 들이 push 를 skip 하도록.
    private(set) var isApplyingRemoteChange = false

    private init() {}

    // MARK: Lifecycle

    func start(with context: ModelContext) {
        modelContext = context
        guard !didStart else { return }
        didStart = true
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        do {
            hasAccess = try await store.requestFullAccessToReminders()
        } catch {
            hasAccess = false
            return
        }
        guard hasAccess else { return }

        do {
            calendar = try ensureCalendar()
        } catch {
            return
        }

        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.pullAndReconcile() }
        }

        await pullAndReconcile()
    }

    // MARK: Calendar (List)

    private func ensureCalendar() throws -> EKCalendar {
        let existing = store.calendars(for: .reminder).first(where: { $0.title == listName })
        if let existing { return existing }

        let new = EKCalendar(for: .reminder, eventStore: store)
        new.title = listName
        // source 우선순위: 기본 reminder source > iCloud > Local
        new.source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV })
            ?? store.sources.first(where: { $0.sourceType == .local })
            ?? store.sources.first
        try store.saveCalendar(new, commit: true)
        return new
    }

    // MARK: Pull (Reminders → Local)

    func pullAndReconcile() async {
        guard hasAccess, let calendar, let modelContext else { return }

        let predicate = store.predicateForReminders(in: [calendar])
        let reminders = await fetchReminders(matching: predicate)

        var todos: [Todo] = []
        do {
            todos = try modelContext.fetch(FetchDescriptor<Todo>())
        } catch {
            return
        }

        let remindersByID = Dictionary(uniqueKeysWithValues: reminders.map { ($0.calendarItemIdentifier, $0) })
        let todosByReminderID: [String: Todo] = todos.reduce(into: [:]) { acc, t in
            if let rid = t.reminderID { acc[rid] = t }
        }

        isApplyingRemoteChange = true
        defer { isApplyingRemoteChange = false }

        // 1) Reminders 에서 외부 삭제된 항목 → 로컬에서도 삭제
        for todo in todos {
            if let rid = todo.reminderID, remindersByID[rid] == nil {
                modelContext.delete(todo)
            }
        }

        // 2) Reminders 의 각 항목 → 로컬에 반영 (없으면 생성, 있으면 업데이트)
        for reminder in reminders {
            let rid = reminder.calendarItemIdentifier
            if let local = todosByReminderID[rid] {
                apply(reminder, to: local)
            } else {
                let new = Todo(title: reminder.title ?? "", order: todos.count)
                new.reminderID = rid
                apply(reminder, to: new)
                modelContext.insert(new)
            }
        }

        // 3) 아직 reminderID 가 없는 로컬 todo → Reminders 로 push
        for todo in todos where todo.reminderID == nil {
            await push(todo, skipGuard: true)
        }

        try? modelContext.save()
    }

    private func apply(_ reminder: EKReminder, to todo: Todo) {
        todo.title = reminder.title ?? ""
        todo.todoDescription = reminder.notes
        todo.isCompleted = reminder.isCompleted
        if let dc = reminder.dueDateComponents {
            todo.dueDate = Calendar.current.date(from: dc)
        } else {
            todo.dueDate = nil
        }
    }

    // MARK: Push (Local → Reminders)

    func push(_ todo: Todo) async {
        await push(todo, skipGuard: false)
    }

    private func push(_ todo: Todo, skipGuard: Bool) async {
        guard hasAccess, let calendar else { return }
        if !skipGuard, isApplyingRemoteChange { return }
        // 빈 제목 todo (방금 + 눌러서 생성된 placeholder) 는 push 보류
        if todo.title.trimmingCharacters(in: .whitespaces).isEmpty { return }

        let reminder: EKReminder
        if let rid = todo.reminderID,
           let existing = store.calendarItem(withIdentifier: rid) as? EKReminder {
            reminder = existing
        } else {
            reminder = EKReminder(eventStore: store)
            reminder.calendar = calendar
        }

        reminder.title = todo.title
        reminder.notes = todo.todoDescription
        reminder.isCompleted = todo.isCompleted
        if let due = todo.dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: due
            )
        } else {
            reminder.dueDateComponents = nil
        }

        do {
            try store.save(reminder, commit: true)
            todo.reminderID = reminder.calendarItemIdentifier
        } catch {
            // sync 실패해도 로컬 동작은 막지 않음
        }
    }

    // MARK: Delete (Local → Reminders)

    func delete(reminderID: String?) async {
        guard hasAccess, let reminderID,
              let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else { return }
        try? store.remove(reminder, commit: true)
    }

    // MARK: Helpers

    private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { result in
                continuation.resume(returning: result ?? [])
            }
        }
    }
}
