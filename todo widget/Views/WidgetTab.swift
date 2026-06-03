import Foundation

// 위젯 상단 탭. @AppStorage("selectedWidgetTab") 에 rawValue 로 저장된다.
enum WidgetTab: String, CaseIterable, Identifiable {
    case calendar
    case reminders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar:  return "캘린더"
        case .reminders: return "미리 알림"
        }
    }

    var icon: String {
        switch self {
        case .calendar:  return "calendar"
        case .reminders: return "checklist"
        }
    }
}
