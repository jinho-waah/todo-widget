import EventKit
import OSLog
import SwiftData

@MainActor
struct RemindersReconciler {
    func reconcile(
        reminders: [EKReminder],
        in context: ModelContext,
        pushUnsyncedTodo: (Todo) async -> Void
    ) async {
        let todos: [Todo]
        do {
            todos = try context.fetch(FetchDescriptor<Todo>())
        } catch {
            remindersLog.error("fetch todos failed during pull: \(String(describing: error), privacy: .public)")
            return
        }

        let todosByReminderID: [String: Todo] = todos.reduce(into: [:]) { result, todo in
            if let reminderID = todo.reminderID {
                result[reminderID] = todo
            }
        }

        applyMappedReminders(reminders, todosByReminderID: todosByReminderID)
        importReminders(
            reminders,
            existingTodoCount: todos.count,
            todosByReminderID: todosByReminderID,
            context: context
        )

        for todo in todos where todo.reminderID == nil {
            await pushUnsyncedTodo(todo)
        }

        try? context.save()
    }

    private func applyMappedReminders(
        _ reminders: [EKReminder],
        todosByReminderID: [String: Todo]
    ) {
        for reminder in reminders {
            if let local = todosByReminderID[reminder.calendarItemIdentifier] {
                apply(reminder, to: local)
            }
        }
    }

    private func importReminders(
        _ reminders: [EKReminder],
        existingTodoCount: Int,
        todosByReminderID: [String: Todo],
        context: ModelContext
    ) {
        var importedCount = 0
        for reminder in reminders
            where !reminder.isCompleted
                && reminder.calendar.allowsContentModifications
                && todosByReminderID[reminder.calendarItemIdentifier] == nil {
            let todo = Todo(title: reminder.title ?? "", order: existingTodoCount + importedCount)
            todo.reminderID = reminder.calendarItemIdentifier
            apply(reminder, to: todo)
            context.insert(todo)
            importedCount += 1
        }
    }

    private func apply(_ reminder: EKReminder, to todo: Todo) {
        todo.title = reminder.title ?? ""
        todo.todoDescription = reminder.notes
        todo.isCompleted = reminder.isCompleted
        todo.dueDate = reminder.dueDateComponents.flatMap {
            Calendar.current.date(from: $0)
        }
        todo.reminderListID = reminder.calendar.calendarIdentifier
    }
}
