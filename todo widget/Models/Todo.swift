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

    init(title: String = "", todoDescription: String? = nil, order: Int = 0) {
        self.id = UUID()
        self.title = title
        self.todoDescription = todoDescription
        self.dueDate = nil
        self.isCompleted = false
        self.subTodos = []
        self.order = order
        self.createdAt = Date()
        self.reminderID = nil
    }
}
