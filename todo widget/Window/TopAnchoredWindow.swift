import AppKit
import ObjectiveC

// 콘텐츠 크기 변경 시 top을 고정하고 height만 아래로 자라게 한다.
// setFrame 시점에 origin.y 를 즉시 보정해 "bottom-left 고정 → 한 프레임 후 보정"
// 으로 인한 출렁임을 막는다.
//
// 상태는 Swift stored property 가 아닌 associated object 로 저장한다.
// object_setClass 로 클래스를 swap 하면 원본 NSWindow 가 할당하지 않은
// 메모리에 stored property 가 위치해 UB 가 발생하기 때문이다.

private var anchorEnabledKey: UInt8 = 0
private var anchorTopYKey: UInt8 = 0
private var programmaticFrameChangeKey: UInt8 = 0

final class TopAnchoredWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    var anchorEnabled: Bool {
        get { (objc_getAssociatedObject(self, &anchorEnabledKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &anchorEnabledKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var anchorTopY: CGFloat {
        get { (objc_getAssociatedObject(self, &anchorTopYKey) as? CGFloat) ?? 0 }
        set { objc_setAssociatedObject(self, &anchorTopYKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var isProgrammaticFrameChange: Bool {
        get { (objc_getAssociatedObject(self, &programmaticFrameChangeKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &programmaticFrameChangeKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    func enableTopAnchor() {
        anchorTopY = frame.maxY
        anchorEnabled = true
    }

    func refreshTopAnchor() {
        anchorTopY = frame.maxY
        anchorEnabled = true
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        applyFrame(adjusted(frameRect), display: flag, animate: false)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animationFlag: Bool) {
        // animate:true 의 내부 interpolation 경로가 우리의 origin 보정을 우회하면서
        // bottom-left 고정 방식으로 매 프레임을 그리기 때문에 "top 이 내려갔다 올라오는"
        // 점프가 보인다. animation flag 를 무시하고 즉시 최종 frame 으로 설정한다.
        applyFrame(adjusted(frameRect), display: flag, animate: false)
    }

    override func setContentSize(_ size: NSSize) {
        let newFrameRect = frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var newFrame = frame
        newFrame.size = newFrameRect.size
        setFrame(newFrame, display: true)
    }

    override func setFrameOrigin(_ point: NSPoint) {
        if anchorEnabled && !isProgrammaticFrameChange {
            anchorTopY = point.y + frame.size.height
        }
        super.setFrameOrigin(point)
    }

    override func setFrameTopLeftPoint(_ point: NSPoint) {
        if anchorEnabled && !isProgrammaticFrameChange {
            anchorTopY = point.y
        }
        super.setFrameTopLeftPoint(point)
    }

    override func mouseDown(with event: NSEvent) {
        makeKeyAndOrderFront(nil)
        super.mouseDown(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            makeKeyAndOrderFront(nil)
        }
        super.sendEvent(event)
    }

    private func adjusted(_ rect: NSRect) -> NSRect {
        guard anchorEnabled else { return rect }
        // AppKit/SwiftUI 가 content fitting 중 같은 size 의 frame 을 다시 제안할 때가
        // 있다. 이때 origin 은 현재 widget 위치가 아니라 시스템이 다시 계산한 위치일 수
        // 있으므로 그대로 받으면 add/delete 때 창이 중앙 쪽으로 튄다.
        if rect.size == frame.size {
            return frame
        }

        var adjustedFrame = rect
        adjustedFrame.origin.x = frame.origin.x
        adjustedFrame.origin.y = anchorTopY - rect.size.height
        return adjustedFrame
    }

    private func applyFrame(_ frame: NSRect, display flag: Bool, animate: Bool) {
        isProgrammaticFrameChange = true
        defer { isProgrammaticFrameChange = false }
        super.setFrame(frame, display: flag, animate: animate)
    }
}
