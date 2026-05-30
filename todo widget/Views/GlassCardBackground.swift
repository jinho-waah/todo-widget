import SwiftUI

// 위젯 외곽 카드 — macOS 26 Liquid Glass 채택.
// `.glassEffect(.regular, in: shape)` 가 specular highlight / 다이내믹 tint / 라이트·다크
// 적응을 모두 system 이 처리하므로 이전의 material+tint+stroke+highlight 4겹 overlay 를
// 모두 제거했다. 데스크탑에서 떠 있는 느낌을 위한 long-distance ambient shadow 만 남긴다.

struct GlassCardBackground: View {
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
    }

    var body: some View {
        // compositingGroup 으로 glass 의 alpha 를 먼저 하나로 합쳐 두지 않으면
        // `.shadow` 가 Color.clear 의 사각형 bounding box 를 따라 halo 를 만들 위험이 있다.
        Color.clear
            .glassEffect(.regular, in: shape)
            .compositingGroup()
            .shadow(color: DesignTokens.shadowDeep,  radius: 60, y: 24)
            .shadow(color: DesignTokens.shadowClose, radius: 8,  y: 2)
    }
}
