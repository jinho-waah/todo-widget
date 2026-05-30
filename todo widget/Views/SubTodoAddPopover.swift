import SwiftUI

struct SubTodoAddPopover: View {
    @Binding var title: String
    let onCancel: () -> Void
    let onSubmit: () -> Void

    @FocusState private var titleFocused: Bool

    private var isSubmitDisabled: Bool {
        title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopoverHeader(title: "세부 할일", onClose: nil)

            Divider().padding(.horizontal, 8)

            TextField("제목", text: $title)
                .textFieldStyle(.plain)
                .font(DesignTokens.subTodoFont)
                .foregroundStyle(DesignTokens.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .focused($titleFocused)
                .onSubmit { submitIfPossible() }

            Divider().padding(.horizontal, 8)

            HStack {
                Button("취소", action: onCancel)
                    .buttonStyle(.glass)

                Spacer()

                Button("추가", action: submitIfPossible)
                    .buttonStyle(.glassProminent)
                    .disabled(isSubmitDisabled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .padding(.vertical, 4)
        .frame(width: 220)
        .onAppear { titleFocused = true }
    }

    private func submitIfPossible() {
        guard !isSubmitDisabled else { return }
        onSubmit()
    }
}
