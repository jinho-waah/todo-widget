import SwiftUI

// 완료 체크 후 자동 삭제까지 남은 시간을 보여주는 뱃지.
// 탭하면 onCancel 호출 (체크 해제 → 삭제 취소).

struct CountdownBadge: View {
    let seconds: Int
    let total: Int
    let tint: Color
    let onCancel: () -> Void

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(seconds) / Double(total)
    }

    var body: some View {
        Button(action: onCancel) {
            ZStack {
                Circle()
                    .stroke(Color.black.opacity(0.10), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        tint.opacity(0.80),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                Text("\(seconds)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeInOut(duration: 0.3), value: seconds)
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help("탭하면 완료 취소")
    }
}
