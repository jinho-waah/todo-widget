import AppKit
import SwiftUI

@MainActor
@Observable
final class EditTodoFormStore {
    struct State {
        var title: String
        var desc: String
        var availableLists: [ReminderList] = []
        var showCreateListForm = false
    }

    enum Intent {
        case appeared
        case updateTitle(String)
        case updateDescription(String)
        case selectList(todo: Todo, String?)
        case showCreateListForm(Bool)
        case createReminderList(todo: Todo, title: String, color: NSColor)
        case setDueDate(todo: Todo, Date?)
        case addDateIfNeeded(todo: Todo)
        case clearTime(todo: Todo)
        case addTimeIfNeeded(todo: Todo)
        case save(todo: Todo, dismiss: DismissAction)
        case dismiss(DismissAction)
    }

    var state: State
    let isNew: Bool

    init(todo: Todo) {
        self.state = State(
            title: todo.title,
            desc: todo.todoDescription ?? ""
        )
        self.isNew = todo.title.isEmpty
    }

    func send(_ intent: Intent) {
        switch intent {
        case .appeared:
            state.availableLists = RemindersSync.shared.availableLists()
            Task { @MainActor in
                await RemindersSync.shared.refresh()
                state.availableLists = RemindersSync.shared.availableLists()
            }

        case .updateTitle(let title):
            state.title = title

        case .updateDescription(let desc):
            state.desc = desc

        case .selectList(let todo, let listID):
            todo.reminderListID = listID

        case .showCreateListForm(let visible):
            state.showCreateListForm = visible

        case .createReminderList(let todo, let title, let color):
            Task { @MainActor in
                if let listID = await RemindersSync.shared.createList(named: title, color: color) {
                    state.availableLists = RemindersSync.shared.availableLists()
                    todo.reminderListID = listID
                    state.showCreateListForm = false
                }
            }

        case .setDueDate(let todo, let date):
            todo.dueDate = date

        case .addDateIfNeeded(let todo):
            if todo.dueDate == nil {
                todo.dueDate = Calendar.current.startOfDay(for: Date())
            }

        case .clearTime(let todo):
            if let date = todo.dueDate {
                todo.dueDate = Calendar.current.startOfDay(for: date)
            }

        case .addTimeIfNeeded(let todo):
            guard !hasTime(todo), let date = todo.dueDate else { return }
            let now = Date()
            let cal = Calendar.current
            var comps = cal.dateComponents([.year, .month, .day], from: date)
            comps.hour = cal.component(.hour, from: now)
            comps.minute = cal.component(.minute, from: now)
            todo.dueDate = cal.date(from: comps)

        case .save(let todo, let dismiss):
            let title = state.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return }
            todo.title = title
            let desc = state.desc.trimmingCharacters(in: .whitespaces)
            todo.todoDescription = desc.isEmpty ? nil : desc
            Task { await RemindersSync.shared.push(todo) }
            dismiss()

        case .dismiss(let dismiss):
            dismiss()
        }
    }

    func hasTime(_ todo: Todo) -> Bool {
        guard let date = todo.dueDate else { return false }
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return components.hour != 0 || components.minute != 0
    }
}
