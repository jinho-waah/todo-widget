import SwiftUI
import UniformTypeIdentifiers

// MARK: - ReorderDropDelegate
//
// Todo / SubTodo 양쪽에서 동일하게 쓰는 드래그-재정렬 delegate.
// 두 모델의 차이 (SubTodo 는 같은 부모 children 끼리만 재정렬 허용) 는
// `canReorder` 클로저로 흡수한다.
//
// Item 은 SwiftData @Model 이므로 class 다 → AnyObject. id 는 UUID.

struct ReorderDropDelegate<Item: AnyObject & Identifiable>: DropDelegate where Item.ID == UUID {
    let target: Item
    let siblings: [Item]
    let isEditMode: Bool
    /// dragging item 이 이 target 과 reorder 가능한지 (e.g. 같은 parent 인지) 검사.
    let canReorder: (Item) -> Bool
    /// 재정렬 결과를 모델에 반영. 보통 `{ $0.order = $1 }`.
    let setOrder: (Item, Int) -> Void
    @Binding var dragging: Item?
    @Binding var dropTargetID: UUID?

    func performDrop(info: DropInfo) -> Bool {
        commitReorder()
        withAnimation(DesignTokens.toggleSpring) {
            dragging = nil
            dropTargetID = nil
        }
        return true
    }

    func dropEntered(info: DropInfo) {
        guard isEditMode,
              let d = dragging,
              d.id != target.id,
              canReorder(d)
        else { return }
        withAnimation(DesignTokens.toggleSpring) {
            dropTargetID = target.id
        }
    }

    func dropExited(info: DropInfo) {
        if dropTargetID == target.id {
            withAnimation(DesignTokens.toggleSpring) {
                dropTargetID = nil
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isEditMode, let d = dragging, canReorder(d) else {
            return DropProposal(operation: .forbidden)
        }
        return DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        guard isEditMode, let d = dragging else { return false }
        return canReorder(d)
    }

    // 실제 순서 변경은 drop 시점에 한 번만 적용 → 드래그 중 row 들이 흔들리지 않고
    // 파란 highlight 만으로 "여기로 떨어집니다" 를 보여준 뒤 손을 뗄 때 정착.
    private func commitReorder() {
        guard isEditMode,
              let d = dragging,
              d.id != target.id,
              canReorder(d),
              let from = siblings.firstIndex(where: { $0.id == d.id }),
              let to   = siblings.firstIndex(where: { $0.id == target.id }),
              from != to
        else { return }

        var arr = siblings
        arr.move(
            fromOffsets: IndexSet(integer: from),
            toOffset: to > from ? to + 1 : to
        )
        withAnimation(DesignTokens.layoutSpring) {
            for (i, item) in arr.enumerated() { setOrder(item, i) }
        }
    }
}

// MARK: - ReorderDropResetDelegate
//
// 컨테이너 (리스트 / sub-todo 그룹) 자체에 부착되는 fallback delegate.
// row delegate 가 한 번도 호출되지 못한 채 drop 이 끝났거나, 빈 영역에서
// 손을 떼는 경우 dragging/highlight 상태를 초기화한다.

struct ReorderDropResetDelegate<Item: AnyObject>: DropDelegate {
    @Binding var dragging: Item?
    @Binding var dropTargetID: UUID?

    func performDrop(info: DropInfo) -> Bool {
        withAnimation(DesignTokens.toggleSpring) {
            dragging = nil
            dropTargetID = nil
        }
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
