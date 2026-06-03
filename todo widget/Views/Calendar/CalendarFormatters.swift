import Foundation

// 캘린더 일정 표시용 캐싱 포맷터. (DateFormatters 의 캘린더 버전 — 매 row 재할당 회피)
@MainActor
enum CalendarFormatters {
    /// 시각 — "오후 3:00" / "3:00 PM" (locale 결정)
    static let time: DateFormatter = make(template: "jmm")
    /// 아젠다 섹션 헤더 — "5월 30일 (금)" / "May 30 (Fri)"
    static let sectionDate: DateFormatter = make(template: "MMMdEEE")
    /// 월 네비 타이틀 — "2026년 5월" / "May 2026"
    static let monthTitle: DateFormatter = make(template: "yMMMM")

    private static func make(template: String) -> DateFormatter {
        let df = DateFormatter()
        df.locale = .userPreferred
        df.setLocalizedDateFormatFromTemplate(template)
        return df
    }

    /// 일정의 시간 라벨. 종일이면 "종일", 아니면 시작시각(같은 날 종료면 "시작–종료").
    static func timeLabel(for event: CalendarEvent) -> String {
        if event.isAllDay { return "종일" }
        let start = time.string(from: event.start)
        if Calendar.current.isDate(event.start, inSameDayAs: event.end) {
            return "\(start) – \(time.string(from: event.end))"
        }
        return start
    }
}
