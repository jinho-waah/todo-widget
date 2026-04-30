import SwiftUI
import SwiftData
import AppKit
import HotKey
import ObjectiveC

// MARK: - Notifications

extension Notification.Name {
    /// SwiftUI body 의 intrinsic content height 가 변할 때 AppDelegate 로 통지.
    static let widgetContentHeightChanged = Notification.Name("widgetContentHeightChanged")
    /// 편집(재정렬) 모드 진입/종료 시 통지. AppDelegate 가 윈도우 드래그를 토글.
    static let widgetEditModeChanged = Notification.Name("widgetEditModeChanged")
}

// MARK: - Top-Anchored Window
// 콘텐츠 크기 변경 시 top을 고정하고 height만 아래로 자라게 한다.
// setFrame 시점에 origin.y 를 즉시 보정해 "bottom-left 고정 → 한 프레임 후 보정"
// 으로 인한 출렁임을 막는다.
//
// ⚠️ 상태는 Swift stored property 가 아닌 associated object 로 저장한다.
//    object_setClass 로 클래스를 swap 하면 원본 NSWindow 가 할당하지 않은
//    메모리에 stored property 가 위치해 UB 가 발생하기 때문.

private var anchorEnabledKey: UInt8 = 0
private var anchorTopYKey: UInt8 = 0

final class TopAnchoredWindow: NSWindow {
    var anchorEnabled: Bool {
        get { (objc_getAssociatedObject(self, &anchorEnabledKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &anchorEnabledKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var anchorTopY: CGFloat {
        get { (objc_getAssociatedObject(self, &anchorTopYKey) as? CGFloat) ?? 0 }
        set { objc_setAssociatedObject(self, &anchorTopYKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    func enableTopAnchor() {
        anchorTopY = frame.maxY
        anchorEnabled = true
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(adjusted(frameRect), display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animationFlag: Bool) {
        // animate:true 의 내부 interpolation 경로가 우리의 origin 보정을 우회하면서
        // bottom-left 고정 방식으로 매 프레임을 그리기 때문에 "top 이 내려갔다 올라오는"
        // 점프가 보인다. animation flag 를 무시하고 즉시 최종 frame 으로 설정 →
        // SwiftUI 가 내부 content 를 부드럽게 애니메이트 하는 동안 윈도우는 매 프레임
        // 정확히 top-anchored 상태로 따라온다.
        super.setFrame(adjusted(frameRect), display: flag, animate: false)
    }

    override func setContentSize(_ size: NSSize) {
        // setContentSize 는 origin 을 그대로 둔 채 size 만 바꾸므로
        // 직접 새 frame 을 계산해 setFrame 으로 통과시킨다 (→ 우리의 adjusted 적용).
        let newFrameRect = frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var newFrame = frame
        newFrame.size = newFrameRect.size
        setFrame(newFrame, display: true)
    }

    override func setFrameOrigin(_ point: NSPoint) {
        // 사용자가 창을 이동 → 새 top 을 anchor 로 갱신
        if anchorEnabled {
            anchorTopY = point.y + frame.size.height
        }
        super.setFrameOrigin(point)
    }

    override func setFrameTopLeftPoint(_ point: NSPoint) {
        if anchorEnabled { anchorTopY = point.y }
        super.setFrameTopLeftPoint(point)
    }

    private func adjusted(_ rect: NSRect) -> NSRect {
        guard anchorEnabled else { return rect }
        // 사이즈 변경이 없는 순수 이동인 경우 anchor 갱신만 하고 그대로 통과
        if rect.size == frame.size {
            anchorTopY = rect.maxY
            return rect
        }
        var f = rect
        f.origin.y = anchorTopY - rect.size.height
        return f
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var toggleHotKey: HotKey?
    private var heightObserver: NSObjectProtocol?
    private var editModeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { self.configureWindow() }
        registerGlobalHotKey()
        registerContentHeightObserver()
        registerEditModeObserver()
    }

    deinit {
        if let obs = heightObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = editModeObserver { NotificationCenter.default.removeObserver(obs) }
    }

    // MARK: Edit-mode (drag disable)

    private func registerEditModeObserver() {
        editModeObserver = NotificationCenter.default.addObserver(
            forName: .widgetEditModeChanged,
            object: nil,
            queue: .main
        ) { note in
            guard let editing = note.object as? Bool,
                  let window = NSApp.windows.first else { return }
            // 편집 모드 → 윈도우 background 드래그 비활성화 (drop reorder 와 충돌 방지)
            window.isMovableByWindowBackground = !editing
        }
    }

    // MARK: Manual window sizing
    // SwiftUI 의 .windowResizability(.contentSize) 가 window animator 를 거쳐
    // 매 프레임 bottom-left 고정으로 보간하는 문제를 우회하려고, 윈도우 크기를
    // 우리가 직접 driving 한다. SwiftUI body 가 intrinsic height 를 알려주면
    // animate:false 로 즉시 setFrame 호출 → 항상 top-anchored.

    private func registerContentHeightObserver() {
        heightObserver = NotificationCenter.default.addObserver(
            forName: .widgetContentHeightChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let h = note.object as? CGFloat else { return }
            self?.applyContentHeight(h)
        }
    }

    private func applyContentHeight(_ contentHeight: CGFloat) {
        guard contentHeight > 0,
              let window = NSApp.windows.first as? TopAnchoredWindow else { return }
        let contentRect = NSRect(origin: .zero, size: NSSize(width: DesignTokens.widgetWidth, height: contentHeight))
        let frameSize = window.frameRect(forContentRect: contentRect).size
        var newFrame = window.frame
        newFrame.size = frameSize
        newFrame.origin.y = window.anchorTopY - frameSize.height
        if newFrame != window.frame {
            window.setFrame(newFrame, display: true, animate: false)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { sender.windows.first?.makeKeyAndOrderFront(nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: Global Hotkey (⌥ + `)

    private func registerGlobalHotKey() {
        let hotKey = HotKey(key: .grave, modifiers: [.option])
        hotKey.keyDownHandler = { [weak self] in
            self?.toggleWindow()
        }
        toggleHotKey = hotKey
    }

    private func toggleWindow() {
        guard let window = NSApp.windows.first else { return }
        if NSApp.isActive && window.isVisible && window.isKeyWindow {
            NSApp.hide(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func configureWindow() {
        guard let window = NSApp.windows.first else { return }
        window.styleMask = [.borderless, .resizable]
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()

        window.hasShadow = true

        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = DesignTokens.cornerRadius
            contentView.layer?.cornerCurve = .continuous
            contentView.layer?.masksToBounds = true
        }

        // 윈도우 자체의 implicit animation 을 끔 → AppKit 이 자체적으로 frame 을
        // interpolate 하면서 우리의 setFrame override 를 우회하는 일을 막는다.
        window.animationBehavior = .none

        // 윈도우 클래스를 TopAnchoredWindow 로 교체 → 이후의 모든 setFrame 이
        // top 을 고정한 채 height 만 변하도록 보정됨.
        object_setClass(window, TopAnchoredWindow.self)
        (window as? TopAnchoredWindow)?.enableTopAnchor()
    }
}

@main
struct todo_widgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = {
        // VersionedSchema + SchemaMigrationPlan 으로 후속 변경 시 lightweight/custom
        // migration 을 끼워 넣을 수 있게 한다 (Models/TodoSchema.swift 참고).
        let schema = Schema(versionedSchema: TodoSchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        // 1차: 정상 경로 (마이그레이션 plan 적용)
        if let container = try? ModelContainer(
            for: schema,
            migrationPlan: TodoMigrationPlan.self,
            configurations: [config]
        ) {
            return container
        }

        // 2차: 마이그레이션 자체가 실패한 진짜 corruption 케이스에만 store 를 폐기.
        // V1 만 있는 현재로선 거의 발생하지 않지만, 여전히 사용자 데이터를 통째로
        // 날리는 동작이므로 plan 경로를 우선 시도한 뒤에만 도달한다.
        try? FileManager.default.removeItem(at: config.url)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            TodoListView()
        }
        .modelContainer(sharedModelContainer)
        // .windowResizability(.contentSize) 제거 → 윈도우 크기는 AppDelegate 가
        // SwiftUI body 의 intrinsic height 통지를 받아 직접 setFrame 으로 driving.
        .defaultSize(width: 340, height: 200)
    }
}
