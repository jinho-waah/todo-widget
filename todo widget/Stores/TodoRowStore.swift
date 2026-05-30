import AppKit
import SwiftData
import SwiftUI

@MainActor
@Observable
final class TodoRowStore {
    enum MoreMenuContent: Equatable {
        case closed
        case actions
        case editForm
        case createList
    }

    struct State {
        var moreMenu: MoreMenuContent = .closed
        var availableLists: [ReminderList] = []
        var showSubTodoPopover = false
        var newSubTodoTitle = ""
        var draggingSubTodo: SubTodo?
        var subDropTargetID: UUID?
        var countdownRemaining: Int?
    }

    enum Intent {
        case toggleCompletion(todo: Todo, context: ModelContext, deleteDelay: Int)
        case cancelCompletionCountdown(todo: Todo)
        case rowDisappeared
        case autoOpenEditFormIfNeeded(Todo)
        case moreMenuChanged(previous: MoreMenuContent, current: MoreMenuContent, todo: Todo, context: ModelContext)
        case openActions
        case closeMoreMenu
        case showEditForm
        case showCreateList
        case selectList(todo: Todo, listID: String?)
        case deleteTodo(todo: Todo, context: ModelContext)
        case createReminderList(todo: Todo, title: String, color: NSColor)
        case showSubTodoPopover(Bool)
        case updateNewSubTodoTitle(String)
        case cancelSubTodo
        case submitSubTodo(todo: Todo, context: ModelContext)
    }

    var state = State()

    @ObservationIgnored private var countdownTask: Task<Void, Never>?

    func send(_ intent: Intent) {
        switch intent {
        case .toggleCompletion(let todo, let context, let deleteDelay):
            withAnimation(DesignTokens.toggleSpring) { todo.isCompleted.toggle() }
            Task { await RemindersSync.shared.push(todo) }

            if todo.isCompleted {
                startCompletionCountdown(todo: todo, context: context, delay: deleteDelay)
            } else {
                stopCompletionCountdown()
            }

        case .cancelCompletionCountdown(let todo):
            stopCompletionCountdown()
            guard todo.isCompleted else { return }
            withAnimation(DesignTokens.toggleSpring) { todo.isCompleted = false }
            Task { await RemindersSync.shared.push(todo) }

        case .rowDisappeared:
            stopCompletionCountdown()

        case .autoOpenEditFormIfNeeded(let todo):
            Task { @MainActor in
                guard todo.title.isEmpty else { return }
                try? await Task.sleep(for: DesignTokens.rowAppearSettleDelay)
                if todo.title.isEmpty { state.moreMenu = .editForm }
            }

        case .moreMenuChanged(let previous, let current, let todo, let context):
            guard previous == .editForm, current != .editForm else { return }
            if todo.title.trimmingCharacters(in: .whitespaces).isEmpty {
                let rid = todo.reminderID
                withAnimation(DesignTokens.layoutSpring) { context.delete(todo) }
                Task { await RemindersSync.shared.delete(reminderID: rid) }
            } else {
                Task { await RemindersSync.shared.push(todo) }
            }

        case .openActions:
            state.availableLists = RemindersSync.shared.availableLists()
            state.moreMenu = .actions
            Task { @MainActor in
                await RemindersSync.shared.refresh()
                state.availableLists = RemindersSync.shared.availableLists()
            }

        case .closeMoreMenu:
            state.moreMenu = .closed

        case .showEditForm:
            state.moreMenu = .editForm

        case .showCreateList:
            state.moreMenu = .createList

        case .selectList(let todo, let listID):
            state.moreMenu = .closed
            Task { await RemindersSync.shared.move(todo, toListID: listID) }

        case .deleteTodo(let todo, let context):
            state.moreMenu = .closed
            let rid = todo.reminderID
            withAnimation(DesignTokens.layoutSpring) { context.delete(todo) }
            Task { await RemindersSync.shared.delete(reminderID: rid) }

        case .createReminderList(let todo, let title, let color):
            Task { @MainActor in
                if let listID = await RemindersSync.shared.createList(named: title, color: color) {
                    state.availableLists = RemindersSync.shared.availableLists()
                    await RemindersSync.shared.move(todo, toListID: listID)
                    state.moreMenu = .closed
                }
            }

        case .showSubTodoPopover(let visible):
            state.showSubTodoPopover = visible

        case .updateNewSubTodoTitle(let title):
            state.newSubTodoTitle = title

        case .cancelSubTodo:
            state.newSubTodoTitle = ""
            state.showSubTodoPopover = false

        case .submitSubTodo(let todo, let context):
            let trimmed = state.newSubTodoTitle.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            let sub = SubTodo(title: trimmed, order: todo.subTodos.count)
            sub.parent = todo
            withAnimation(DesignTokens.layoutSpring) {
                context.insert(sub)
                todo.subTodos.append(sub)
            }
            state.newSubTodoTitle = ""
            state.showSubTodoPopover = false
        }
    }

    private func startCompletionCountdown(todo: Todo, context: ModelContext, delay rawDelay: Int) {
        stopCompletionCountdown()

        let delay = max(rawDelay, 0)
        guard delay > 0 else {
            deleteLocallyAfterCompletion(todo, context: context)
            return
        }

        state.countdownRemaining = delay
        countdownTask = Task { @MainActor in
            for remaining in stride(from: delay, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                state.countdownRemaining = remaining
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            deleteLocallyAfterCompletion(todo, context: context)
        }
    }

    private func stopCompletionCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        state.countdownRemaining = nil
    }

    private func deleteLocallyAfterCompletion(_ todo: Todo, context: ModelContext) {
        stopCompletionCountdown()
        guard todo.isCompleted else { return }
        withAnimation(DesignTokens.layoutSpring) {
            context.delete(todo)
        }
    }
}
