import EventKit
import OSLog
import SwiftData

@MainActor
struct RemindersReconciler {
    func reconcile(
        reminders: [EKReminder],
        in context: ModelContext,
        belongsToDefaultCalendar: (EKReminder) -> Bool,
        pushUnsyncedTodo: (Todo) async -> Void
    ) async {
        let todos: [Todo]
        do {
            todos = try context.fetch(FetchDescriptor<Todo>())
        } catch {
            remindersLog.error("fetch todos failed during pull: \(String(describing: error), privacy: .public)")
            return
        }

        let remindersByID = Dictionary(uniqueKeysWithValues: reminders.map {
            ($0.calendarItemIdentifier, $0)
        })
        let todosByReminderID: [String: Todo] = todos.reduce(into: [:]) { result, todo in
            if let reminderID = todo.reminderID {
                result[reminderID] = todo
            }
        }

        deleteLocallyRemovedRemoteItems(todos: todos, remindersByID: remindersByID, context: context)
        applyMappedReminders(reminders, todosByReminderID: todosByReminderID)
        importDefaultListReminders(
            reminders,
            existingTodoCount: todos.count,
            todosByReminderID: todosByReminderID,
            context: context,
            belongsToDefaultCalendar: belongsToDefaultCalendar
        )

        for todo in todos where todo.reminderID == nil {
            await pushUnsyncedTodo(todo)
        }

        try? context.save()
    }

    private func deleteLocallyRemovedRemoteItems(
        todos: [Todo],
        remindersByID: [String: EKReminder],
        context: ModelContext
    ) {
        for todo in todos {
            if let reminderID = todo.reminderID, remindersByID[reminderID] == nil {
                context.delete(todo)
            }
        }
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

    private func importDefaultListReminders(
        _ reminders: [EKReminder],
        existingTodoCount: Int,
        todosByReminderID: [String: Todo],
        context: ModelContext,
        belongsToDefaultCalendar: (EKReminder) -> Bool
    ) {
        var importedCount = 0
        for reminder in reminders
            where belongsToDefaultCalendar(reminder)
                && !reminder.isCompleted
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
