import SwiftUI
import SwiftData

struct SubTodoRowView: View {
    @Bindable var subTodo: SubTodo
    var isEditMode: Bool = false
    @Environment(\.modelContext) private var modelContext

    @State private var store = SubTodoRowStore()
    @FocusState private var editFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                store.send(.toggleCompletion(subTodo))
            } label: {
                checkboxLabel
            }
            .buttonStyle(.plain)
            .disabled(isEditMode)
            .opacity(isEditMode ? DesignTokens.disabledOpacity : 1.0)

            Text(subTodo.title)
                .font(DesignTokens.subTodoFont)
                .tracking(-0.05)
                .foregroundStyle(subTodo.isCompleted ? DesignTokens.textCompleted : DesignTokens.textSubTodo)
                .strikethrough(subTodo.isCompleted)

            Spacer(minLength: 0)

            Button {
                store.send(.showActions(true))
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.dotColor)
                    .frame(width: DesignTokens.menuButton, height: DesignTokens.menuButton)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isEditMode)
            .opacity(isEditMode ? DesignTokens.disabledOpacity : 1.0)
            .popover(isPresented: showActionsBinding, arrowEdge: .trailing) {
                RowActionsPopover(
                    onEdit: {
                        store.send(.beginEdit(subTodo))
                    },
                    onDelete: {
                        store.send(.delete(subTodo, modelContext))
                    }
                )
            }
            .popover(isPresented: showEditFormBinding, arrowEdge: .trailing) {
                editFormView
            }
        }
        .padding(.leading, DesignTokens.subIndent)
        .padding(.vertical, 4)
        .animation(DesignTokens.toggleSpring, value: isEditMode)
    }

    private var showActionsBinding: Binding<Bool> {
        Binding(
            get: { store.state.showActions },
            set: { store.send(.showActions($0)) }
        )
    }

    private var showEditFormBinding: Binding<Bool> {
        Binding(
            get: { store.state.showEditForm },
            set: { if !$0 { store.send(.closeEditForm) } }
        )
    }

    private var editTitleBinding: Binding<String> {
        Binding(
            get: { store.state.editTitle },
            set: { store.send(.updateEditTitle($0)) }
        )
    }

    @ViewBuilder
    private var checkboxLabel: some View {
        ZStack {
            if subTodo.isCompleted {
                Circle().fill(DesignTokens.systemBlue)
                LinearGradient(
                    colors: [DesignTokens.subCheckboxHighlight, .clear],
                    startPoint: .top,
                    endPoint: .init(x: 0.5, y: 0.55)
                )
                .clipShape(Circle())
                Image(systemName: "checkmark")
                    .font(.system(size: DesignTokens.subCheckbox * 0.40, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().fill(DesignTokens.subCheckboxFill)
                Circle().stroke(DesignTokens.subCheckBorder, lineWidth: 1.4)
            }
        }
        .frame(width: DesignTokens.subCheckbox, height: DesignTokens.subCheckbox)
        .animation(DesignTokens.toggleSpring, value: subTodo.isCompleted)
    }

    // MARK: Edit Form

    private var editFormView: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopoverHeader(title: "수정") { store.send(.closeEditForm) }

            Divider().padding(.horizontal, 8)

            TextField("제목", text: editTitleBinding)
                .textFieldStyle(.plain)
                .font(DesignTokens.subTodoFont)
                .foregroundStyle(DesignTokens.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .focused($editFieldFocused)
                .onSubmit { saveEdit() }

            Divider().padding(.horizontal, 8)

            HStack {
                Button("취소") { store.send(.closeEditForm) }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.textSecondary)
                Spacer()
                Button("저장") { saveEdit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.state.editTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .padding(.vertical, 4)
        .frame(width: 220)
        .onAppear { editFieldFocused = true }
    }

    private func saveEdit() {
        store.send(.saveEdit(subTodo))
    }
}
