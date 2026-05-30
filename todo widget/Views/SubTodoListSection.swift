import SwiftUI
import UniformTypeIdentifiers

struct SubTodoListSection: View {
    let subTodos: [SubTodo]
    let isEditMode: Bool
    @Binding var draggingSubTodo: SubTodo?
    @Binding var dropTargetID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(subTodos) { subTodo in
                SubTodoRowView(subTodo: subTodo, isEditMode: isEditMode)
                    .reorderableRow(
                        item: subTodo,
                        siblings: subTodos,
                        isEditMode: isEditMode,
                        highlightCornerRadius: 8,
                        highlightInset: -2,
                        canReorder: { $0.parent?.id == subTodo.parent?.id },
                        dragging: $draggingSubTodo,
                        dropTargetID: $dropTargetID
                    ) {
                        dragPreview(for: subTodo)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .padding(.top, 8)
        .transition(.opacity)
        .onDrop(of: [.text], delegate: ReorderDropResetDelegate<SubTodo>(
            dragging: $draggingSubTodo,
            dropTargetID: $dropTargetID
        ))
    }

    private func dragPreview(for subTodo: SubTodo) -> some View {
        Text(subTodo.title)
            .font(DesignTokens.subTodoFont)
            .foregroundStyle(DesignTokens.textSubTodo)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
