import SwiftData
import SwiftUI

@MainActor
@Observable
final class SubTodoRowStore {
    struct State {
        var showActions = false
        var showEditForm = false
        var editTitle = ""
    }

    enum Intent {
        case toggleCompletion(SubTodo)
        case showActions(Bool)
        case beginEdit(SubTodo)
        case delete(SubTodo, ModelContext)
        case updateEditTitle(String)
        case saveEdit(SubTodo)
        case closeEditForm
    }

    var state = State()

    func send(_ intent: Intent) {
        switch intent {
        case .toggleCompletion(let subTodo):
            withAnimation(DesignTokens.toggleSpring) { subTodo.isCompleted.toggle() }

        case .showActions(let visible):
            state.showActions = visible

        case .beginEdit(let subTodo):
            state.showActions = false
            Task { @MainActor in
                try? await Task.sleep(for: DesignTokens.popoverChainDelay)
                state.editTitle = subTodo.title
                state.showEditForm = true
            }

        case .delete(let subTodo, let context):
            state.showActions = false
            withAnimation(DesignTokens.layoutSpring) { context.delete(subTodo) }

        case .updateEditTitle(let title):
            state.editTitle = title

        case .saveEdit(let subTodo):
            let trimmed = state.editTitle.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            subTodo.title = trimmed
            state.showEditForm = false

        case .closeEditForm:
            state.showEditForm = false
        }
    }
}
