import SwiftUI

enum ScrollEdgeDirection {
    case up
    case down
}

struct ScrollEdgeIndicator: View {
    let direction: ScrollEdgeDirection
    let visible: Bool
    let onTap: () -> Void

    private var alignment: Alignment {
        direction == .up ? .top : .bottom
    }

    private var gradientStart: UnitPoint {
        direction == .up ? .bottom : .top
    }

    private var gradientEnd: UnitPoint {
        direction == .up ? .top : .bottom
    }

    private var iconName: String {
        direction == .up ? "chevron.up" : "chevron.down"
    }

    private var edgePadding: Edge.Set {
        direction == .up ? .top : .bottom
    }

    var body: some View {
        ZStack(alignment: alignment) {
            LinearGradient(
                colors: [
                    Color.black.opacity(0),
                    Color(light: .black.opacity(0.18), dark: .black.opacity(0.42))
                ],
                startPoint: gradientStart,
                endPoint: gradientEnd
            )
            .frame(height: 56)
            .allowsHitTesting(false)

            Button(action: onTap) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(edgePadding, 2)
        }
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
    }
}
