import AppKit
import ObjectiveC

/// 위젯 윈도우의 모든 lifecycle / presentation / sizing 을 책임진다.
///
/// AppDelegate 는 이 컨트롤러를 소유하고 thin coordinator 역할만 하며, 윈도우와 관련된
/// 의사결정은 전부 여기서 이뤄진다.
///
/// **핵심 기능**
/// - SwiftUI 가 만든 NSWindow 의 클래스를 TopAnchoredWindow 로 swap 해 top-anchored resize 활성화
/// - widget collection behavior (`.moveToActiveSpace + .fullScreenAuxiliary`) 적용
/// - SwiftUI body 의 intrinsic height 알림을 받아 윈도우 frame 을 즉시 (animate:false) 갱신
/// - ⌃+1 단축키로부터의 toggle 처리
/// - edit (재정렬) 모드 진입 시 윈도우 background drag 비활성화
@MainActor
final class WidgetWindowController: NSObject, NSWindowDelegate {
    /// SwiftUI WindowGroup 의 단일 윈도우. attach() 이후 강한 참조로 보관 — NSApp.windows.first
    /// 는 panel·popover 등 부수 윈도우가 끼면 다른 인스턴스를 돌려줄 수 있어 fragile.
    private(set) var window: TopAnchoredWindow?

    private var isEditMode = false

    /// SwiftUI body 의 첫 height 알림이 attach() 의 class swap 보다 빨리 도착할 수 있으므로,
    /// 직전 측정값을 보관해 swap 직후 다시 한 번 적용한다.
    private var pendingContentHeight: CGFloat = 0

    private let collectionBehavior: NSWindow.CollectionBehavior = [
        .moveToActiveSpace,
        .fullScreenAuxiliary
    ]

    // MARK: - Lifecycle

    /// SwiftUI 가 생성한 첫 윈도우를 가져와 위젯용 설정을 적용하고 TopAnchoredWindow 로 swap 한다.
    /// applicationDidFinishLaunching 직후 `DispatchQueue.main.async` 안에서 호출돼야 한다 —
    /// SwiftUI 가 NSWindow 를 다음 runloop 에 만들기 때문.
    func attach() {
        guard let rawWindow = NSApp.windows.first else { return }
        applyBaseConfiguration(rawWindow)

        // SwiftUI 가 만든 NSWindow 의 클래스를 TopAnchoredWindow 로 swap → top-anchored resize 활성화.
        object_setClass(rawWindow, TopAnchoredWindow.self)
        guard let anchored = rawWindow as? TopAnchoredWindow else { return }
        anchored.enableTopAnchor()
        window = anchored

        DispatchQueue.main.async { [weak self] in
            self?.applyFittingContentSize()
        }
    }

    // MARK: - Public API

    /// 외부 (AppDelegate.applicationDidBecomeActive / applicationShouldHandleReopen) 에서
    /// 윈도우 presentation 을 재적용해야 할 때 호출.
    func restorePresentation() {
        guard let window else { return }
        applyPresentation(window)
    }

    /// 윈도우 visibility 토글. 보이고 focus 됐으면 숨기고, 아니면 현재 Space 로 끌고 와서 띄움.
    func toggleVisibility() {
        guard let window else { return }
        let visibleAndFocused = window.isVisible && window.isKeyWindow && NSApp.isActive
        if visibleAndFocused {
            window.orderOut(nil)
        } else {
            applyPresentation(window)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()

            // makeKeyAndOrderFront 직후 macOS 가 윈도우 frame 을 재계산하면서 우리의
            // top-anchor 가 일시적으로 흔들릴 수 있어, 다음 runloop 에 한 번 더 보정.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let window else { return }
                self?.applyPresentation(window)
            }
        }
    }

    /// 편집 (재정렬) 모드 진입/종료. 윈도우 background drag 를 토글해 drop reorder 와 충돌 방지.
    func setEditMode(_ editing: Bool) {
        isEditMode = editing
        window?.isMovableByWindowBackground = !editing
    }

    /// SwiftUI body 의 intrinsic height 변경을 윈도우 frame 으로 반영. animate:false 로 즉시 적용 —
    /// 윈도우 자체의 animator 가 한 번 더 보간하면 top-anchor 가 출렁여 보임.
    func applyContentHeight(_ contentHeight: CGFloat) {
        guard contentHeight > 0 else { return }
        pendingContentHeight = contentHeight
        guard let window else { return }

        let cappedHeight = min(contentHeight, DesignTokens.widgetMaxHeight)
        let contentRect = NSRect(
            origin: .zero,
            size: NSSize(width: DesignTokens.widgetWidth, height: cappedHeight)
        )
        let targetFrameSize = window.frameRect(forContentRect: contentRect).size
        var targetFrame = window.frame
        targetFrame.size = targetFrameSize
        targetFrame.origin.y = window.anchorTopY - targetFrameSize.height

        guard targetFrame != window.frame else { return }
        window.setFrame(targetFrame, display: true, animate: false)
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // LSUIElement: X 버튼은 종료가 아니라 숨김. 사용자는 ⌃+1 로 재호출, ⌘Q 로 종료.
        sender.orderOut(nil)
        return false
    }

    // MARK: - Private

    private func applyBaseConfiguration(_ window: NSWindow) {
        window.styleMask = [.borderless, .resizable]
        window.isMovableByWindowBackground = !isEditMode
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .normal
        window.collectionBehavior = collectionBehavior
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.hasShadow = true
        // 윈도우 자체의 implicit animation 차단 → AppKit 이 frame interpolation 으로
        // 우리의 setFrame override 를 우회하는 일을 막는다.
        window.animationBehavior = .none

        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = DesignTokens.cornerRadius
            contentView.layer?.cornerCurve = .continuous
            contentView.layer?.masksToBounds = true
        }
    }

    private func applyPresentation(_ window: TopAnchoredWindow) {
        window.level = .normal
        window.collectionBehavior = collectionBehavior
        window.isMovableByWindowBackground = !isEditMode
        window.refreshTopAnchor()
        applyFittingContentSize()
    }

    /// 윈도우 contentView 의 fittingSize 를 사용해 현재 height 를 한 번 더 적용.
    /// SwiftUI 가 onGeometryChange 로 보내준 pending 값이 있으면 그걸 우선.
    private func applyFittingContentSize() {
        guard let window, let contentView = window.contentView else { return }
        contentView.layoutSubtreeIfNeeded()

        if pendingContentHeight > 0 {
            applyContentHeight(pendingContentHeight)
            return
        }

        let fittingHeight = contentView.fittingSize.height
        if fittingHeight.isFinite, fittingHeight > 0 {
            applyContentHeight(fittingHeight)
        }
    }
}
