import SwiftUI

// itsycal 그리드의 단일 날짜 셀. 날짜 숫자 + (있으면) 캘린더 색 점.
// 오늘은 파란 링, 선택일은 채워진 디스크로 구분한다.
struct CalendarDayCell: View {
    let dayNumber: Int
    let isInDisplayedMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let isHoliday: Bool
    let eventColors: [Color]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                ZStack {
                    if isSelected {
                        Circle().fill(DT.blue)
                    } else if isToday {
                        Circle().strokeBorder(DT.blue.opacity(0.85), lineWidth: 1.5)
                    }
                    Text("\(dayNumber)")
                        .font(.system(size: 12, weight: isToday || isSelected ? .semibold : .regular))
                        .foregroundStyle(numberColor)
                }
                .frame(width: 24, height: 24)

                // 일정 색 점 (최대 3). 자리 차지를 위해 빈 줄도 같은 높이 유지.
                HStack(spacing: 3) {
                    ForEach(Array(eventColors.enumerated()), id: \.offset) { _, color in
                        Circle().fill(color).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var numberColor: Color {
        if isSelected { return .white }
        if !isInDisplayedMonth { return (isHoliday ? DT.red : DesignTokens.textMeta).opacity(0.6) }
        if isHoliday { return DT.red }
        if isToday { return DT.blueText }
        return DesignTokens.textPrimary
    }
}
