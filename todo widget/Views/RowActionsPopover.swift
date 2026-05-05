import SwiftUI

// Todo / SubTodo row 의 "수정 / 삭제" 액션 팝오버.
// 두 호출부의 구조가 동일하므로 onEdit / onDelete 클로저만 다르게 주입.

struct RowActionsPopover: View {
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionButton(label: "수정", icon: "pencil", color: DesignTokens.textPrimary, action: onEdit)
            Divider().padding(.horizontal, 8)
            actionButton(label: "삭제", icon: "trash", color: DesignTokens.overdueColor, action: onDelete)
        }
        .padding(.vertical, 4)
        .frame(width: 140)
    }

    private func actionButton(
        label: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(color)
    }
}
