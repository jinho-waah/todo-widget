import AppKit
import HotKey

/// 위젯 앱의 진입점. 자기 자신은 책임을 거의 갖지 않고, 세 개의 focused controller 에 위임한다:
///
/// - `WidgetWindowController` — 윈도우 lifecycle / sizing / level / behavior
/// - `GlobalHotkeyController` — ⌃+1 단축키
/// - `MainMenuBuilder` — LSUIElement 환경의 keyboard equivalent 활성용 menu
///
/// 그 외엔 `NSApplicationDelegate` 의 system hook 들을 윈도우 컨트롤러로 라우팅하고,
/// `WidgetWindowChannel` 의 두 콜백 (height / edit-mode) 을 윈도우 컨트롤러에 연결한다.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowController = WidgetWindowController()
    private var hotkeyController: GlobalHotkeyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI 가 NSWindow 를 다음 runloop 에 만들기 때문에 async 한 박자 늦춤.
        DispatchQueue.main.async { [windowController] in
            windowController.attach()
        }
        MainMenuBuilder.install()
        registerGlobalHotKey()
        subscribeToWidgetChannel()
    }

    // MARK: - NSApplicationDelegate hooks

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // LSUIElement: 마지막 창 닫혀도 앱 유지 (단축키로 재호출 가능).
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            windowController.restorePresentation()
            windowController.window?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        windowController.restorePresentation()
        // 앱 시작 시 권한이 거부됐다가 사용자가 System Settings 에서 켜준 경우 자동 복구용.
        Task { @MainActor in
            await RemindersSync.shared.refresh()
            await CalendarService.shared.refresh()
        }
    }

    // MARK: - Wiring

    private func registerGlobalHotKey() {
        hotkeyController = GlobalHotkeyController(key: .one, modifiers: [.control]) { [weak self] in
            self?.windowController.toggleVisibility()
        }
    }

    /// SwiftUI / Store → 윈도우로의 단방향 이벤트를 컨트롤러에 위임.
    private func subscribeToWidgetChannel() {
        WidgetWindowChannel.shared.onContentHeightChanged = { [weak self] height in
            self?.windowController.applyContentHeight(height)
        }
        WidgetWindowChannel.shared.onEditModeChanged = { [weak self] editing in
            self?.windowController.setEditMode(editing)
        }
    }
}
