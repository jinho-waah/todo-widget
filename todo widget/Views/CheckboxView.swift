import SwiftUI

struct CheckboxView: View {
    let isCompleted: Bool
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isCompleted {
                    Circle().fill(DesignTokens.systemBlue)
                    // inner top highlight
                    LinearGradient(
                        colors: [DesignTokens.checkboxHighlight, .clear],
                        startPoint: .top,
                        endPoint: .init(x: 0.5, y: 0.55)
                    )
                    .clipShape(Circle())
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Circle().fill(DesignTokens.checkboxFill)
                    Circle().stroke(DesignTokens.checkboxBorder, lineWidth: 1.5)
                }
            }
            .frame(width: size, height: size)
            .animation(DesignTokens.toggleSpring, value: isCompleted)
        }
        .buttonStyle(.plain)
    }
}
