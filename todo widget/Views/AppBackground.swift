import SwiftUI

// dark-mode-spec §7 — 라이트/다크 자동 분기 그라데이션 백드롭.
// 라이트: 분홍-보라-라벤더-청록 / 다크: 딥 인디고-퍼플-블루-청록.
// TodoListView 에 자동 적용하지 않음. 필요 시 root에서 ZStack { AppBackground(); ... } 으로 wire-in.

struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private var stops: [Gradient.Stop] {
        if colorScheme == .dark {
            return [
                .init(color: Color(red: 0.10, green: 0.04, blue: 0.18), location: 0.00),  // #1A0B2E
                .init(color: Color(red: 0.24, green: 0.11, blue: 0.36), location: 0.28),  // #3D1B5C
                .init(color: Color(red: 0.12, green: 0.23, blue: 0.54), location: 0.58),  // #1E3A8A
                .init(color: Color(red: 0.06, green: 0.30, blue: 0.36), location: 1.00),  // #0F4C5C
            ]
        } else {
            return [
                .init(color: Color(red: 1.00, green: 0.42, blue: 0.62), location: 0.00),  // #FF6B9D
                .init(color: Color(red: 0.75, green: 0.42, blue: 1.00), location: 0.28),  // #C06CFE
                .init(color: Color(red: 0.43, green: 0.54, blue: 1.00), location: 0.58),  // #6E8AFF
                .init(color: Color(red: 0.31, green: 0.82, blue: 0.77), location: 1.00),  // #4FD1C5
            ]
        }
    }

    var body: some View {
        LinearGradient(
            stops: stops,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
