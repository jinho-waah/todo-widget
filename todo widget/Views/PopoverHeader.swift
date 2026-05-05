import SwiftUI

// 팝오버 상단 라벨 + 닫기 X 버튼.
// EditTodoFormView, TodoRowView 의 sub-todo 추가 popover, SubTodoRowView 의
// edit form 이 같은 머리 형태를 쓰므로 한 곳으로 모은다.

struct PopoverHeader: View {
    let title: String
    // nil 이면 우측 X 버튼을 숨긴다. macOS 의 popover 는 바깥 클릭으로
    // 자연 dismiss 되므로 X 가 어색한 화면에서는 호출 측이 nil 을 넘긴다.
    let onClose: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.textMeta)
                .tracking(0.3)
            Spacer()
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DesignTokens.dotColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
