import AppKit
import SwiftUI

// 캘린더 탭의 뷰 상태(표시 월 / 선택일 / 권한 배너). 데이터 싱글턴 CalendarService 와는 별개로
// "지금 어떤 달·날짜를 보고 있나" 만 들고 있다. TodoListStore 의 캘린더 버전.
@MainActor
@Observable
final class CalendarStore {
    struct State {
        var displayedMonth: Date
        var selectedDate: Date
    }

    enum Intent {
        case start
        case prevMonth
        case nextMonth
        case jumpToToday
        case selectDay(Date)
        case permissionBannerTapped
    }

    var state: State
    let service = CalendarService.shared

    private let calendar = Calendar.current

    init() {
        let cal = Calendar.current
        let today = Date()
        state = State(
            displayedMonth: cal.startOfMonth(for: today),
            selectedDate: cal.startOfDay(for: today)
        )
    }

    func send(_ intent: Intent) {
        switch intent {
        case .start:
            service.start(month: state.displayedMonth)

        case .prevMonth:
            shiftMonth(by: -1)

        case .nextMonth:
            shiftMonth(by: 1)

        case .jumpToToday:
            let today = Date()
            withAnimation(DesignTokens.toggleSpring) {
                state.displayedMonth = calendar.startOfMonth(for: today)
                state.selectedDate = calendar.startOfDay(for: today)
            }
            Task { await service.setMonth(state.displayedMonth) }

        case .selectDay(let day):
            let dayStart = calendar.startOfDay(for: day)
            withAnimation(DesignTokens.toggleSpring) {
                state.selectedDate = dayStart
                // 흘림 셀(이전/다음 달)을 누르면 그 달로 이동.
                let dayMonth = calendar.startOfMonth(for: dayStart)
                if dayMonth != state.displayedMonth {
                    state.displayedMonth = dayMonth
                }
            }
            Task { await service.setMonth(state.displayedMonth) }

        case .permissionBannerTapped:
            switch service.status {
            case .denied:
                openCalendarPrivacySettings()
            case .notDetermined, .requestFailed, .unknown:
                Task { await service.requestAccessFromUser(month: state.displayedMonth) }
            case .requesting, .granted:
                break
            }
        }
    }

    private func shiftMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: state.displayedMonth) else { return }
        withAnimation(DesignTokens.toggleSpring) {
            state.displayedMonth = calendar.startOfMonth(for: next)
        }
        Task { await service.setMonth(state.displayedMonth) }
    }

    // MARK: Permission banner (RemindersPermissionBanner 재사용)

    var showsPermissionBanner: Bool {
        service.status != .unknown && service.status != .granted
    }

    var permissionTitle: String {
        switch service.status {
        case .denied:        return "캘린더 권한이 꺼져 있습니다"
        case .requesting:    return "캘린더 권한을 요청하는 중입니다"
        case .requestFailed: return "캘린더 권한 요청이 필요합니다"
        default:             return "캘린더 권한이 필요합니다"
        }
    }

    var permissionSubtitle: String {
        switch service.status {
        case .denied:     return "탭하여 시스템 설정 열기"
        case .requesting: return "시스템 권한 창을 확인해주세요"
        default:          return "탭하여 접근 요청하기"
        }
    }

    private func openCalendarPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }
}
