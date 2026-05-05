import SwiftUI
import UniformTypeIdentifiers

// MARK: - Reorderable Row Modifier
//
// edit-mode 에서 활성화되는 드래그-드롭 wrapper.
// drop highlight, opacity / scale, drag 시작, ReorderDropDelegate 부착을
// 한 곳으로 모아 Todo / SubTodo row 양쪽이 같은 modifier 를 쓰도록 한다.
//
// 차이는 호출부에서 파라미터로 흡수:
//   - 하이라이트 corner radius / inset (Todo 10/-4, SubTodo 8/-2)
//   - drag preview view (다른 폰트·색)
//   - canReorder 규칙 (SubTodo 는 같은 parent 만)

extension View {
    func reorderableRow<Item: Reorderable, Preview: View>(
        item: Item,
        siblings: [Item],
        isEditMode: Bool,
        highlightCornerRadius: CGFloat = 10,
        highlightInset: CGFloat = -4,
        canReorder: @escaping (Item) -> Bool = { _ in true },
        dragging: Binding<Item?>,
        dropTargetID: Binding<UUID?>,
        @ViewBuilder dragPreview: @escaping () -> Preview
    ) -> some View {
        modifier(ReorderableRowModifier(
            item: item,
            siblings: siblings,
            isEditMode: isEditMode,
            highlightCornerRadius: highlightCornerRadius,
            highlightInset: highlightInset,
            canReorder: canReorder,
            dragging: dragging,
            dropTargetID: dropTargetID,
            dragPreview: dragPreview
        ))
    }
}

private struct ReorderableRowModifier<Item: Reorderable, Preview: View>: ViewModifier {
    let item: Item
    let siblings: [Item]
    let isEditMode: Bool
    let highlightCornerRadius: CGFloat
    let highlightInset: CGFloat
    let canReorder: (Item) -> Bool
    @Binding var dragging: Item?
    @Binding var dropTargetID: UUID?
    @ViewBuilder let dragPreview: () -> Preview

    private var isDragging: Bool { dragging?.id == item.id }
    private var isDropTarget: Bool {
        isEditMode && dropTargetID == item.id && dragging?.id != item.id
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: highlightCornerRadius, style: .continuous)
                    .fill(isDropTarget ? DesignTokens.systemBlue.opacity(0.10) : Color.clear)
                    .padding(.horizontal, highlightInset)
            )
            // row 의 빈(글자 없는) 영역까지 hit-test 가 닿도록 컨테이너 전체를 클릭 가능 영역으로.
            // 이게 없으면 SwiftUI 가 그려진 픽셀에만 hit-test 를 허용해 드래그가 안 잡힘.
            .contentShape(Rectangle())
            .opacity(isEditMode && isDragging ? 0.35 : 1.0)
            .scaleEffect(isEditMode && isDragging ? 0.98 : 1.0, anchor: .center)
            .animation(DesignTokens.toggleSpring, value: isDragging)
            .animation(DesignTokens.toggleSpring, value: isDropTarget)
            .onDrag {
                guard isEditMode else { return NSItemProvider() }
                dragging = item
                return NSItemProvider(object: item.id.uuidString as NSString)
            } preview: {
                dragPreview()
            }
            .onDrop(
                of: [.text],
                delegate: ReorderDropDelegate(
                    target: item,
                    siblings: siblings,
                    isEditMode: isEditMode,
                    canReorder: canReorder,
                    dragging: $dragging,
                    dropTargetID: $dropTargetID
                )
            )
    }
}
