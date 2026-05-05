import Foundation

// drag-to-reorder UI 가 다루는 모델 공통 인터페이스.
//
// `Identifiable` 을 직접 상속하면 SwiftData @Model 이 합성하는 `Identifiable`
// (ID = PersistentIdentifier 와 우리가 선언한 `id: UUID` 사이에서 ambiguous)
// 와 충돌하므로, 상속 대신 `id: UUID` 를 raw requirement 로 둔다.

protocol Reorderable: AnyObject {
    var id: UUID { get }
    var order: Int { get set }
}

extension Todo: Reorderable {}
extension SubTodo: Reorderable {}
