import AppKit
import SwiftData
import SwiftUI

@MainActor
@Observable
final class TodoListStore {
    struct State {
        var isEditMode = false
        var draggingTodo: Todo?
        var dropTargetID: UUID?
        var hasMoreBelow = false
        var hasMoreAbove = false
    }

    enum Intent {
        case startSync(ModelContext)
        case addTodo(todos: [Todo], context: ModelContext)
        case setEditMode(Bool)
        case setScrollEdges(above: Bool, below: Bool)
        case widgetHeightChanged(CGFloat)
        case permissionBannerTapped
    }

    var state = State()
    let sync = RemindersSync.shared

    var showsPermissionBanner: Bool {
        sync.status != .unknown && sync.status != .granted
    }

    var remindersPermissionTitle: String {
        switch sync.status {
        case .denied:
            return "미리 알림 권한이 꺼져 있습니다"
        case .requesting:
            return "미리 알림 권한을 요청하는 중입니다"
        case .requestFailed:
            return "미리 알림 권한 요청이 필요합니다"
        default:
            return "미리 알림 권한이 필요합니다"
        }
    }

    var remindersPermissionSubtitle: String {
        switch sync.status {
        case .denied:
            return "탭하여 시스템 설정 열기"
        case .requesting:
            return "시스템 권한 창을 확인해주세요"
        case .requestFailed:
            return sync.lastRequestError ?? "탭하여 다시 요청하기"
        default:
            return "탭하여 접근 요청하기"
        }
    }

    func send(_ intent: Intent) {
        switch intent {
        case .startSync(let context):
            sync.start(with: context)

        case .addTodo(let todos, let context):
            withAnimation(DesignTokens.layoutSpring) {
                let newTodo = Todo(title: "", order: todos.count)
                context.insert(newTodo)
            }

        case .setEditMode(let editing):
            withAnimation(DesignTokens.toggleSpring) {
                state.isEditMode = editing
            }
            WidgetWindowChannel.shared.reportEditModeChanged(editing)

        case .setScrollEdges(let above, let below):
            withAnimation(.easeOut(duration: 0.18)) {
                state.hasMoreAbove = above
                state.hasMoreBelow = below
            }

        case .widgetHeightChanged(let height):
            WidgetWindowChannel.shared.reportContentHeight(height)

        case .permissionBannerTapped:
            switch sync.status {
            case .denied:
                openRemindersPrivacySettings()
            case .notDetermined, .requestFailed, .unknown:
                Task { await RemindersSync.shared.requestAccessFromUser() }
            case .requesting, .granted:
                break
            }
        }
    }

    private func openRemindersPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
