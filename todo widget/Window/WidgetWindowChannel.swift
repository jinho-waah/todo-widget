import Foundation

/// SwiftUI body (TodoListView · TodoListStore) → AppKit (AppDelegate) 단방향 이벤트 채널.
///
/// 기존엔 `NotificationCenter` 의 `Notification.Name` 두 개로 같은 일을 했는데,
/// `note.object as? Bool` / `as? CGFloat` force-cast 와 implicit subscriber binding 의
/// 두 가지 fragility 가 있었다. 이 클래스는:
///
/// - **Type-safe**: payload 가 CGFloat / Bool 로 강제됨. 컴파일 타임에 검증.
/// - **Single consumer**: AppDelegate 하나만 구독. closure 가 nil 이면 no-op.
/// - **@MainActor**: 모든 호출이 메인 스레드 — view body / window mutation 양쪽 안전.
///
/// 호출 패턴:
///   producer (Store) → `report*(...)`
///   consumer (AppDelegate) → init 에서 `on* = { ... }` 콜백 설치
@MainActor
final class WidgetWindowChannel {
    static let shared = WidgetWindowChannel()

    /// SwiftUI body 의 intrinsic content height 변경 시 호출.
    var onContentHeightChanged: ((CGFloat) -> Void)?

    /// 편집(재정렬) 모드 진입/종료 시 호출. payload 는 진입 여부.
    var onEditModeChanged: ((Bool) -> Void)?

    private init() {}

    func reportContentHeight(_ height: CGFloat) {
        onContentHeightChanged?(height)
    }

    func reportEditModeChanged(_ isEditing: Bool) {
        onEditModeChanged?(isEditing)
    }
}
