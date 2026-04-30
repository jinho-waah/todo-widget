import SwiftUI
import SwiftData

struct SubTodoRowView: View {
    @Bindable var subTodo: SubTodo
    var isEditMode: Bool = false
    @Environment(\.modelContext) private var modelContext

    @State private var showActions = false
    @State private var showEditForm = false
    @State private var editTitle = ""
    @FocusState private var editFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(DesignTokens.toggleSpring) { subTodo.isCompleted.toggle() }
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
                showActions = true
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
            .popover(isPresented: $showActions, arrowEdge: .trailing) {
                actionsPopover
            }
            .popover(isPresented: $showEditForm, arrowEdge: .trailing) {
                editFormView
            }
        }
        .padding(.leading, DesignTokens.subIndent)
        .padding(.vertical, 4)
        .animation(DesignTokens.toggleSpring, value: isEditMode)
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

    // MARK: Actions Popover

    private var actionsPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showActions = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    editTitle = subTodo.title
                    showEditForm = true
                }
            } label: {
                Label("수정", systemImage: "pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.textPrimary)

            Divider().padding(.horizontal, 8)

            Button {
                showActions = false
                withAnimation(DesignTokens.layoutSpring) { modelContext.delete(subTodo) }
            } label: {
                Label("삭제", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.overdueColor)
        }
        .padding(.vertical, 4)
        .frame(width: 140)
    }

    // MARK: Edit Form

    private var editFormView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("수정")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.textMeta)
                    .tracking(0.3)
                Spacer()
                Button { showEditForm = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DesignTokens.dotColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider().padding(.horizontal, 8)

            TextField("제목", text: $editTitle)
                .textFieldStyle(.plain)
                .font(DesignTokens.subTodoFont)
                .foregroundStyle(DesignTokens.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .focused($editFieldFocused)
                .onSubmit { saveEdit() }

            Divider().padding(.horizontal, 8)

            HStack {
                Button("취소") { showEditForm = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.textSecondary)
                Spacer()
                Button("저장") { saveEdit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(editTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .padding(.vertical, 4)
        .frame(width: 220)
        .onAppear { editFieldFocused = true }
    }

    private func saveEdit() {
        let trimmed = editTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        subTodo.title = trimmed
        showEditForm = false
    }
}
