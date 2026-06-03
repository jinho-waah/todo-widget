import AppKit
import ObjectiveC

// 위젯 윈도우의 위치를 "사용자가 마지막으로 둔 좌상단" 에 고정한다.
//
// 위치의 단일 권위는 anchor(좌상단 = anchorLeftX, anchorTopY = frame.maxY) 하나다.
//
//  - **리사이즈**(콘텐츠 높이 변경): anchor 를 그대로 두고 top-left 를 anchor 에 맞춰 아래로만
//    자란다 (origin.y = anchorTopY − height). 높이가 바뀌어도 좌상단은 고정.
//  - **사용자 드래그**: anchor 를 새 좌상단으로 갱신한다. 단, 갱신은 `setFrameOrigin` 이 아니라
//    델리게이트의 `windowDidMove` 에서 한다 — `isMovableByWindowBackground` 드래그는
//    윈도우 서버 레벨에서 직접 이동하느라 `setFrameOrigin`/`setFrameTopLeftPoint` 를 **거치지
//    않기** 때문이다. 예전 코드는 그 override 로 드래그를 잡으려 했지만 한 번도 호출되지 않아
//    anchor 가 런치 위치에 박제됐고, 그래서 "위치를 옮겨도 높이가 바뀌면 처음 생성된 위치로
//    되돌아가는" 버그가 났다. (로그로 확인: 드래그 중 setFrameOrigin 호출 0회.)
//  - **화면 밖 복구**(Spaces/디스플레이 변경): `recoverOntoScreen()` 이 anchor 를 visibleFrame
//    안으로 clamp 한 뒤 다시 적용한다. activate / 화면구성 변경 시점에만 호출 — 리사이즈
//    경로에선 절대 부르지 않는다(위치가 높이에 종속되면 탭 전환 때 출렁임).
//
// 상태는 object_setClass 로 클래스를 swap 하므로 Swift stored property 가 아닌
// associated object 로 저장한다 (원본 NSWindow 에 슬롯이 없어 stored property 는 UB).

private var anchorEnabledKey: UInt8 = 0
private var anchorTopYKey: UInt8 = 0
private var anchorLeftXKey: UInt8 = 0
private var isAdjustingFrameKey: UInt8 = 0

final class TopAnchoredWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    var anchorEnabled: Bool {
        get { (objc_getAssociatedObject(self, &anchorEnabledKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &anchorEnabledKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// 좌상단 y (= frame.maxY).
    var anchorTopY: CGFloat {
        get { (objc_getAssociatedObject(self, &anchorTopYKey) as? CGFloat) ?? 0 }
        set { objc_setAssociatedObject(self, &anchorTopYKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// 좌상단 x (= frame.minX).
    var anchorLeftX: CGFloat {
        get { (objc_getAssociatedObject(self, &anchorLeftXKey) as? CGFloat) ?? 0 }
        set { objc_setAssociatedObject(self, &anchorLeftXKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    // setFrame 재진입 가드. AppKit 의 setFrame(_:display:animate:false) 는 내부에서
    // self.setFrame(_:display:) 를 다시 부르고, 그게 우리 override → super(animate:false) →
    // 다시 self.setFrame(_:display:) … 로 무한 재귀(스택 오버플로 크래시)한다. 첫 진입에서만
    // 앵커 보정을 적용하고, 재진입한 호출은 그대로 super 로 흘려보내 AppKit 내부 흐름이
    // 정상 종료되게 한다.
    private var isAdjustingFrame: Bool {
        get { (objc_getAssociatedObject(self, &isAdjustingFrameKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &isAdjustingFrameKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    // MARK: - Anchor 설정/채택

    /// class swap 직후 1회. 현재 좌상단을 앵커로 삼고 활성화.
    func enableTopAnchor() {
        anchorLeftX = frame.minX
        anchorTopY = frame.maxY
        anchorEnabled = true
    }

    /// 사용자 드래그로 창이 실제로 옮겨졌을 때 현재 좌상단을 앵커로 채택 (windowDidMove 에서 호출).
    func adoptCurrentFrameAsAnchor() {
        anchorLeftX = frame.minX
        anchorTopY = frame.maxY
    }

    // MARK: - 리사이즈 (top-left 고정)

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        guard anchorEnabled, !isAdjustingFrame else {
            super.setFrame(frameRect, display: flag)
            return
        }
        isAdjustingFrame = true
        defer { isAdjustingFrame = false }
        super.setFrame(anchoredResize(frameRect.size), display: flag, animate: false)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animationFlag: Bool) {
        guard anchorEnabled, !isAdjustingFrame else {
            super.setFrame(frameRect, display: flag, animate: animationFlag)
            return
        }
        // animate:true 의 내부 interpolation 은 bottom-left 기준으로 보간해 top 이 출렁이므로
        // animation flag 를 무시하고 즉시 최종 frame 으로 설정.
        isAdjustingFrame = true
        defer { isAdjustingFrame = false }
        super.setFrame(anchoredResize(frameRect.size), display: flag, animate: false)
    }

    override func setContentSize(_ size: NSSize) {
        let frameSize = frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        // 가드가 걸린 setFrame override 를 통해 적용 (super 직접 호출 시 재귀 가능).
        setFrame(NSRect(origin: frame.origin, size: frameSize), display: true)
    }

    /// 들어온 size 로, origin 은 앵커 좌상단에 맞춘 frame. 제안된 origin 은 무시한다.
    /// top(=anchorTopY) 과 left(=anchorLeftX) 를 height 와 무관하게 고정 → 높이만 아래로 변함.
    private func anchoredResize(_ size: NSSize) -> NSRect {
        guard anchorEnabled else { return NSRect(origin: frame.origin, size: size) }
        return NSRect(x: anchorLeftX, y: anchorTopY - size.height, width: size.width, height: size.height)
    }

    // MARK: - constrainFrameRect (AppKit 자동 화면제약 차단)

    /// AppKit 은 setFrame(_:display:animate:) 안에서 frame 을 메뉴바 아래/화면 안으로 재배치할
    /// 수 있다. anchor 가 위치의 단일 권위이므로 이 자동 보정을 끈다. 화면 밖 복구는
    /// recoverOntoScreen() 이 명시적 시점에만 담당.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        anchorEnabled ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }

    // MARK: - 화면 밖 복구

    /// 앵커를 현재 스크린 visibleFrame 안으로 clamp 한 뒤 다시 적용. activate / 화면구성 변경
    /// 시점에만 호출. 창이 화면보다 크면 top 을 우선 맞추고 아래는 넘치게 둔다(내부 스크롤이 처리).
    func recoverOntoScreen() {
        guard anchorEnabled, let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let size = frame.size
        var x = anchorLeftX
        var top = anchorTopY
        if x + size.width > visible.maxX { x = visible.maxX - size.width }
        if x < visible.minX { x = visible.minX }
        top = max(top, visible.minY + size.height)  // 바닥이 화면 밖이면 위로 끌어올림
        top = min(top, visible.maxY)                 // top 이 화면 밖이면 내림 (창이 너무 크면 이게 우선)
        anchorLeftX = x
        anchorTopY = top
        setFrame(NSRect(origin: frame.origin, size: size), display: true)
    }

    // MARK: - Focus

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
}
