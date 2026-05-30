import AppKit
import HotKey

/// HotKey 인스턴스의 lifecycle 을 소유한다. instance 가 deinit 되면 hotkey 도 사라지므로
/// 호출자는 controller 를 강하게 잡아둬야 한다.
@MainActor
final class GlobalHotkeyController {
    private var hotKey: HotKey?

    /// - Parameters:
    ///   - key: HotKey 라이브러리의 키 enum (예: `.one`).
    ///   - modifiers: 함께 눌러야 할 modifier (예: `[.control]`).
    ///   - handler: 단축키가 눌렸을 때 메인 스레드에서 호출.
    init(key: Key, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) {
        let hotKey = HotKey(key: key, modifiers: modifiers)
        hotKey.keyDownHandler = handler
        self.hotKey = hotKey
    }
}
