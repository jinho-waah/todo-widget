import SwiftUI

// 요일 헤더 + itsycal 6주(42칸) 그리드. 고정 높이 — 스크롤되지 않는다.
struct CalendarGridView: View {
    let displayedMonth: Date
    let selectedDate: Date
    let service: CalendarService
    let onSelectDay: (Date) -> Void

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private var days: [Date] {
        calendar.monthGridDays(for: displayedMonth)
    }

    private var weekdaySymbols: [String] {
        calendar.orderedWeekdaySymbols(locale: .userPreferred)
    }

    var body: some View {
        VStack(spacing: 4) {
            // 요일 헤더 (월이 바뀌어도 고정 — 전환 대상 아님)
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.textMeta)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 18)

            // 날짜 그리드 — 월 단위로 통째 교체하며 crossfade. opacity/scale 은 *render transform*
            // 이라 측정 높이를 바꾸지 않는다 → 윈도우 높이 리포터와 피드백 루프(=AppKit
            // constraint-update watchdog 크래시)를 만들지 않는다. (.push/.move 는 layout 기반이라
            // 전환 중 측정 높이가 출렁여 7→8월 등에서 앱이 튕겼다.)
            dateGrid
                .id(displayedMonth)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
        .padding(.horizontal, 16)
        // 월 전환은 부드러운 easeInOut crossfade.
        .animation(.easeInOut(duration: 0.28), value: displayedMonth)
    }

    private var dateGrid: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(days, id: \.self) { day in
                CalendarDayCell(
                    dayNumber: calendar.component(.day, from: day),
                    isInDisplayedMonth: calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month),
                    isToday: calendar.isDateInToday(day),
                    isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                    isHoliday: service.isHoliday(on: day),
                    eventColors: service.eventColors(forDay: day),
                    onTap: { onSelectDay(day) }
                )
            }
        }
    }
}
