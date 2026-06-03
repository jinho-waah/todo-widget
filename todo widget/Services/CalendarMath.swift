import Foundation

// 캘린더 그리드/윈도우 계산용 Calendar 헬퍼.
extension Calendar {
    /// 주어진 날짜가 속한 달의 1일 00:00.
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? startOfDay(for: date)
    }

    /// itsycal 스타일 6주(42칸) 그리드. firstWeekday 로케일 설정을 반영해
    /// 달의 1일이 포함된 주의 시작일부터 42일을 반환한다.
    func monthGridDays(for month: Date) -> [Date] {
        let monthStart = startOfMonth(for: month)
        let weekday = component(.weekday, from: monthStart)            // 1...7
        let offset = (weekday - firstWeekday + 7) % 7
        guard let gridStart = date(byAdding: .day, value: -offset, to: monthStart) else { return [] }
        return (0..<42).compactMap { date(byAdding: .day, value: $0, to: gridStart) }
    }

    /// firstWeekday 부터 시작하는 한 주의 요일 심볼 (일~토 또는 월~일).
    func orderedWeekdaySymbols(locale: Locale) -> [String] {
        let df = DateFormatter()
        df.locale = locale
        let symbols = df.veryShortStandaloneWeekdaySymbols ?? df.veryShortWeekdaySymbols ?? []
        guard symbols.count == 7 else { return symbols }
        let shift = firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }
}
