import SwiftUI

// 캘린더 / 미리 알림 세그먼트. Liquid Glass 트랙 위에서 선택 pill 이 toggleSpring 으로
// 슬라이드한다. 선택 세그먼트의 tint 는 헤더 active 버튼 톤(DT.headerButton*)을 재사용.
struct WidgetTabBar: View {
    @Binding var selection: WidgetTab
    @Namespace private var pill
    @State private var hovered: WidgetTab?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(WidgetTab.allCases) { tab in
                segment(tab)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 20)
        // 헤더/디바이더와 토글 사이 숨 쉴 공간을 넉넉히. (위 패딩이 너무 좁다는 피드백 반영)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func segment(_ tab: WidgetTab) -> some View {
        let isSelected = selection == tab
        let isHovered = hovered == tab

        return Button {
            guard selection != tab else { return }
            withAnimation(DesignTokens.toggleSpring) { selection = tab }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(-0.2)
            }
            .foregroundStyle(isSelected ? DT.blue : DesignTokens.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    ZStack {
                        Capsule().fill(DT.headerButtonFill(active: true, hovered: false))
                        Capsule().strokeBorder(DT.headerButtonStroke(active: true, hovered: false), lineWidth: 0.5)
                    }
                    .matchedGeometryEffect(id: "pill", in: pill)
                } else if isHovered {
                    Capsule().fill(DT.headerButtonFill(active: false, hovered: true))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                hovered = hovering ? tab : (hovered == tab ? nil : hovered)
            }
        }
    }
}
