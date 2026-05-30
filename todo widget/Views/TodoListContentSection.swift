import SwiftUI
import UniformTypeIdentifiers

struct TodoListContentSection: View {
    let todos: [Todo]
    let isEditMode: Bool
    @Binding var draggingTodo: Todo?
    @Binding var dropTargetID: UUID?

    var body: some View {
        Group {
            if todos.isEmpty {
                emptyState
            } else {
                todoRows
            }
        }
    }

    private var emptyState: some View {
        Text("할일을 추가해보세요")
            .font(DesignTokens.descFont)
            .foregroundStyle(DesignTokens.textSecondary)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
    }

    private var todoRows: some View {
        VStack(spacing: 0) {
            ForEach(todos) { todo in
                TodoListRowContainer(
                    todo: todo,
                    isLast: todo.id == todos.last?.id,
                    isEditMode: isEditMode,
                    todos: todos,
                    draggingTodo: $draggingTodo,
                    dropTargetID: $dropTargetID
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .animation(DesignTokens.layoutSpring, value: todos.map(\.id))
        .onDrop(of: [.text], delegate: ReorderDropResetDelegate<Todo>(
            dragging: $draggingTodo,
            dropTargetID: $dropTargetID
        ))
    }
}

private struct TodoListRowContainer: View {
    let todo: Todo
    let isLast: Bool
    let isEditMode: Bool
    let todos: [Todo]
    @Binding var draggingTodo: Todo?
    @Binding var dropTargetID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            TodoRowView(todo: todo, isEditMode: isEditMode)

            if !isLast {
                Rectangle()
                    .fill(DesignTokens.divider)
                    .frame(height: 0.5)
                    .padding(.leading, DesignTokens.subIndent + 10)
            }
        }
        .reorderableRow(
            item: todo,
            siblings: todos,
            isEditMode: isEditMode,
            dragging: $draggingTodo,
            dropTargetID: $dropTargetID
        ) {
            dragPreview
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
    }

    private var dragPreview: some View {
        Text(todo.title.isEmpty ? "새 할일" : todo.title)
            .font(DesignTokens.todoTitleFont)
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
