import SwiftUI
import AppKit

// MARK: - Color(light:dark:) extension
// macOS 외형(라이트/다크)에 따라 자동 분기되는 dynamic Color.
// view에서 colorScheme 분기 없이 토큰 한 줄로 light/dark 자동 처리.

extension Color {
    init(light: Color, dark: Color) {
        self.init(NSColor(name: nil, dynamicProvider: { appearance in
            switch appearance.name {
            case .darkAqua,
                 .vibrantDark,
                 .accessibilityHighContrastDarkAqua,
                 .accessibilityHighContrastVibrantDark:
                return NSColor(dark)
            default:
                return NSColor(light)
            }
        }))
    }
}

// MARK: - DT (라이트/다크 통합 디자인 토큰)
// dark-mode-spec §5 통합 풀세트.

enum DT {

    // ── System (액션·상태) ──────────────────────────────
    static let blue = Color(red: 10/255, green: 132/255, blue: 255/255)   // #0A84FF (체크박스 fill, light/dark 동일)

    static let blueText = Color(                                          // 강조 텍스트(오늘 등)
        light: Color(red: 10/255,  green: 132/255, blue: 255/255),        // #0A84FF
        dark:  Color(red: 64/255,  green: 156/255, blue: 255/255)         // #409CFF
    )

    static let red = Color(                                               // overdue
        light: Color(red: 255/255, green: 59/255,  blue: 48/255),         // #FF3B30
        dark:  Color(red: 255/255, green: 107/255, blue: 98/255)          // #FF6B62
    )

    // ── 텍스트 (위계 위→아래) ──────────────────────────
    static let textTitle     = Color(light: .black.opacity(0.88), dark: .white.opacity(0.92))
    static let textPrimary   = Color(light: .black.opacity(0.86), dark: .white.opacity(0.92))
    static let textSubTodo   = Color(light: .black.opacity(0.72), dark: .white.opacity(0.78))
    static let textSecondary = Color(light: .black.opacity(0.50), dark: .white.opacity(0.60))
    static let textMeta      = Color(light: .black.opacity(0.45), dark: .white.opacity(0.55))
    static let textDot       = Color(light: .black.opacity(0.40), dark: .white.opacity(0.50))
    static let textCompleted = Color(light: .black.opacity(0.38), dark: .white.opacity(0.40))
    static let textMetaDone  = Color(light: .black.opacity(0.30), dark: .white.opacity(0.30))

    // ── 보더/구분선 ───────────────────────────────────
    static let checkboxBorder = Color(light: .black.opacity(0.32), dark: .white.opacity(0.40))
    static let subCheckBorder = Color(light: .black.opacity(0.27), dark: .white.opacity(0.34))
    static let dividerHeader  = Color(light: .black.opacity(0.09), dark: .white.opacity(0.12))
    static let dividerItem    = Color(light: .black.opacity(0.07), dark: .white.opacity(0.08))

    // ── 헤더 버튼 ────────────────────────────────────
    static let buttonFill      = Color(light: .white.opacity(0.55), dark: .white.opacity(0.13))
    static let buttonStroke    = Color(light: .white.opacity(0.70), dark: .white.opacity(0.25))
    static let buttonHighlight = Color(light: .white.opacity(0.50), dark: .white.opacity(0.18))
    static let buttonIcon      = Color(light: .black.opacity(0.72), dark: .white.opacity(0.82))

    // ── 체크박스 idle fill ────────────────────────────
    static let checkboxIdleFill = Color(light: .white.opacity(0.25), dark: .white.opacity(0.08))
    static let subCheckIdleFill = Color(light: .white.opacity(0.20), dark: .white.opacity(0.06))

    // ── 체크박스 inner highlight (light/dark 동일) ──
    static let checkInnerHL    = Color.white.opacity(0.30)   // 19px용
    static let subCheckInnerHL = Color.white.opacity(0.25)   // 14px용

    // ── 그림자 (light/dark 강도 다름) ────────────────
    static let shadowDeep  = Color(light: .black.opacity(0.28), dark: .black.opacity(0.60))
    static let shadowClose = Color(light: .black.opacity(0.12), dark: .black.opacity(0.35))

    // ── 사이즈 (mode 무관) ───────────────────────────
    static let widgetWidth:  CGFloat = 340
    /// 윈도우 max height. 이를 초과하면 todo 리스트가 내부 ScrollView 로 스크롤된다.
    static let widgetMaxHeight: CGFloat = 980
    static let cornerRadius: CGFloat = 24
    static let checkbox:     CGFloat = 19
    static let subCheckbox:  CGFloat = 14
    static let headerButton: CGFloat = 28
    static let menuButton:   CGFloat = 22
    static let subIndent:    CGFloat = 29

    // ── 타이포 (mode 무관) ───────────────────────────
    static let titleFont:     Font = .system(size: 18, weight: .semibold)
    static let todoTitleFont: Font = .system(size: 14, weight: .medium)
    static let subTodoFont:   Font = .system(size: 13, weight: .regular)
    static let descFont:      Font = .system(size: 12, weight: .regular)
    static let dateFont:      Font = .system(size: 11, weight: .regular)
    static let dateBoldFont:  Font = .system(size: 11, weight: .medium)

    // ── 애니메이션 ───────────────────────────────────
    static let toggleSpring: Animation = .spring(response: 0.3, dampingFraction: 0.7)
    static let layoutSpring: Animation = .spring(response: 0.55, dampingFraction: 0.95)

    /// 새로 생성된 todo row 가 layoutSpring(response: 0.55) 으로 등장한 뒤
    /// 자동으로 편집 popover 를 띄우기까지의 settle delay.
    /// spring 의 ~60% 지점을 노려야 시각적으로 자연스럽다 (전체 spring 이 끝나길
    /// 기다리면 너무 늦고, 0 이면 row 가 그려지기 전에 popover 가 떠 anchor 가 점프).
    /// layoutSpring 을 손대면 이 값도 같이 조정해야 한다.
    static let rowAppearSettleDelay: Duration = .milliseconds(320)

    /// 같은 anchor 에 popover A 를 닫고 popover B 를 여는 chain 에서 필요한
    /// 최소 간격. macOS 가 popover dismiss 를 한 프레임에 처리하지 못하는 케이스가
    /// 있어 이 시간만큼 기다린 뒤 다음 popover 를 띄운다.
    static let popoverChainDelay: Duration = .milliseconds(50)

    // ── Header Button (refined, dark-mode-first) ────
    // 디자인 의도:
    //  - idle: 거의 투명 — 위젯 글래스 위에 살짝 떠 있는 느낌
    //  - hover: 약간 또렷
    //  - active: 파란 tint pill — 아이콘 swap 없이 컬러로만 상태 표현
    static func headerButtonFill(active: Bool, hovered: Bool) -> Color {
        if active {
            return Color(
                light: blue.opacity(0.14),
                dark:  blue.opacity(0.22)
            )
        }
        if hovered {
            return Color(
                light: .white.opacity(0.65),
                dark:  .white.opacity(0.10)
            )
        }
        return Color(
            light: .white.opacity(0.40),
            dark:  .white.opacity(0.05)
        )
    }

    static func headerButtonStroke(active: Bool, hovered: Bool) -> Color {
        if active {
            return Color(
                light: blue.opacity(0.45),
                dark:  blue.opacity(0.55)
            )
        }
        if hovered {
            return Color(
                light: .white.opacity(0.75),
                dark:  .white.opacity(0.22)
            )
        }
        return Color(
            light: .white.opacity(0.55),
            dark:  .white.opacity(0.12)
        )
    }

    static func headerButtonHighlight(active: Bool) -> Color {
        if active {
            return Color(
                light: .white.opacity(0.30),
                dark:  .white.opacity(0.10)
            )
        }
        return Color(
            light: .white.opacity(0.45),
            dark:  .white.opacity(0.08)
        )
    }
}

// MARK: - DesignTokens (view-facing aliases)
//
// 모든 view 코드는 `DesignTokens.X` 를 통해 접근한다. 내부 값은 위쪽 `DT` 의
// light/dark dynamic 토큰을 가리킨다. 두 enum 이 공존하는 이유:
//   • `DT` — 디자인 시스템 정의 (raw colors / sizes / fonts / animations)
//   • `DesignTokens` — view-layer 가 사용하는 안정된 이름 공간 (의미 단위)
// 신규 토큰 추가 시: DT 에 raw 값 정의 → DesignTokens 에 의미 있는 이름으로 alias.

enum DesignTokens {
    // Black hierarchy → DT
    static let titleColor         = DT.textTitle
    static let textPrimary        = DT.textPrimary
    static let textSubTodo        = DT.textSubTodo
    static let textSecondary      = DT.textSecondary
    static let textMeta           = DT.textMeta
    static let textMetaCompleted  = DT.textMetaDone
    static let textCompleted      = DT.textCompleted
    static let dotColor           = DT.textDot
    static let checkboxBorder     = DT.checkboxBorder
    static let subCheckBorder     = DT.subCheckBorder
    static let headerDivider      = DT.dividerHeader
    static let divider            = DT.dividerItem

    // Button / Checkbox → DT
    // (Glass card 자체는 macOS 26 `.glassEffect` 가 처리하므로 별도 토큰 없음.)
    static let buttonFill           = DT.buttonFill
    static let buttonStroke         = DT.buttonStroke
    static let buttonHighlight      = DT.buttonHighlight
    static let checkboxHighlight    = DT.checkInnerHL
    static let subCheckboxHighlight = DT.subCheckInnerHL
    static let checkboxFill         = DT.checkboxIdleFill
    static let subCheckboxFill      = DT.subCheckIdleFill

    // Shadows → DT
    static let shadowDeep           = DT.shadowDeep
    static let shadowClose          = DT.shadowClose

    // System colors → DT
    static let systemBlue           = DT.blue
    static let systemRed            = DT.red
    static let overdueColor         = Color(                                      // delete button
        light: Color(red: 0.88, green: 0.20, blue: 0.20),
        dark:  Color(red: 1.00, green: 0.42, blue: 0.38)
    )

    // Background gradient stops (legacy — 라이트만, AppBackground 가 다크/라이트 모두 처리)
    static let gradientStop1        = Color(red: 1.00, green: 0.42, blue: 0.62)
    static let gradientStop2        = Color(red: 0.75, green: 0.42, blue: 1.00)
    static let gradientStop3        = Color(red: 0.43, green: 0.54, blue: 1.00)
    static let gradientStop4        = Color(red: 0.31, green: 0.82, blue: 0.77)

    // Sizes → DT
    static let widgetWidth:        CGFloat = DT.widgetWidth
    static let widgetMaxHeight:    CGFloat = DT.widgetMaxHeight
    static let cornerRadius:       CGFloat = DT.cornerRadius
    static let checkbox:           CGFloat = DT.checkbox
    static let subCheckbox:        CGFloat = DT.subCheckbox
    static let headerButton:       CGFloat = DT.headerButton
    static let menuButton:         CGFloat = DT.menuButton
    static let subIndent:          CGFloat = DT.subIndent

    // Typography → DT
    static let titleFont:          Font = DT.titleFont
    static let todoTitleFont:      Font = DT.todoTitleFont
    static let subTodoFont:        Font = DT.subTodoFont
    static let descFont:           Font = DT.descFont
    static let dateFont:           Font = DT.dateFont
    static let dateFontEmphasized: Font = DT.dateBoldFont

    // Animation → DT
    static let toggleSpring: Animation = DT.toggleSpring
    static let layoutSpring: Animation = DT.layoutSpring
    static let rowAppearSettleDelay: Duration = DT.rowAppearSettleDelay
    static let popoverChainDelay: Duration = DT.popoverChainDelay

    // 편집(재정렬) 모드 진입 시 다른 액션 버튼들에 적용되는 opacity.
    // light/dark 모두에서 "비활성화" 가 인지되도록 충분히 낮게 잡는다.
    static let disabledOpacity: Double = 0.32
}
