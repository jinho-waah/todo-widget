import Foundation
import SwiftData

@Model
final class Todo {
    var id: UUID
    var title: String
    var todoDescription: String?
    var dueDate: Date?
    var isCompleted: Bool
    @Relationship(deleteRule: .cascade) var subTodos: [SubTodo]
    var order: Int
    var createdAt: Date
    /// 미리 알림(EKReminder)의 calendarItemIdentifier. nil 이면 아직 sync 안 됨.
    var reminderID: String?
    /// 이 todo 가 속한 EKCalendar 의 calendarIdentifier. nil 이면 push 시 기본
    /// "todo widget" 캘린더로 resolve. pullAndReconcile 이 reminder.calendar 를
    /// 따라 자동 업데이트 → 사용자가 미리 알림 앱에서 list 를 옮겨도 동기화된다.
    var reminderListID: String?

    init(title: String = "", order: Int = 0) {
        self.id = UUID()
        self.title = title
        self.todoDescription = nil
        self.dueDate = nil
        self.isCompleted = false
        self.subTodos = []
        self.order = order
        self.createdAt = Date()
        self.reminderID = nil
        self.reminderListID = nil
    }
}
