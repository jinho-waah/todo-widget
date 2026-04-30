import SwiftUI

// dark-mode-spec §6 — 라이트/다크 자동 분기 외곽 카드 백그라운드.
// Material만 dynamic Color 처리가 안 되므로 이 view 안에서만 colorScheme 분기.

struct GlassCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private var material: Material {
        colorScheme == .dark ? .thickMaterial : .regularMaterial
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DT.cornerRadius, style: .continuous)
    }

    private var innerHighlight: LinearGradient {
        LinearGradient(
            colors: [DT.glassHighlightTop, .clear],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        shape
            .fill(material)
            .overlay(shape.fill(DT.glassTint))                              // 라이트 white 42% / 다크 .clear
            .overlay(shape.strokeBorder(DT.glassStroke, lineWidth: 0.5))    // 외곽 보더
            .overlay(shape.strokeBorder(innerHighlight, lineWidth: 1))      // 상단 inner highlight
            .shadow(color: DT.shadowDeep,  radius: 60, y: 24)
            .shadow(color: DT.shadowClose, radius: 8,  y: 2)
    }
}
