import SwiftUI

// 캘린더(EKEvent) 레이어의 값 타입. View 는 EventKit 타입을 직접 만지지 않고
// 이 스냅샷 구조체만 다룬다. (RemindersTypes 의 ReminderList 와 대칭)

/// macOS 캘린더의 단일 일정 스냅샷.
struct CalendarEvent: Identifiable, Equatable {
    /// EKEvent.eventIdentifier. 반복 일정은 같은 identifier 가 occurrence 마다 반복되므로
    /// 리스트 식별용 `id` 는 identifier + 시작시각을 합쳐 occurrence 별로 유일하게 만든다.
    let eventID: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let calendarID: String
    let location: String?
    let notes: String?
    /// 공휴일 캘린더("대한민국 공휴일" 등)에서 온 이벤트인지. true 면 아젠다/그리드 점에서는
    /// 제외하고 날짜 셀을 휴일색으로 칠하는 용도로만 쓴다.
    let isHoliday: Bool

    var id: String { "\(eventID)@\(start.timeIntervalSinceReferenceDate)" }
}

/// 일정 생성/편집 폼의 캘린더 픽커용. (ReminderList 와 동형)
struct WritableCalendar: Identifiable {
    let id: String
    let title: String
    let color: Color
}

/// 캘린더(이벤트) 접근 권한 상태. RemindersSyncStatus 와 동형 — 배너 UI 를 공유한다.
enum CalendarAccessStatus {
    case unknown
    case notDetermined
    case requesting
    case requestFailed
    case denied
    case granted
}
