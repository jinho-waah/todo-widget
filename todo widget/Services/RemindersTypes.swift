import SwiftUI

struct ReminderList: Identifiable {
    let id: String
    let title: String
    let color: Color
}

enum RemindersSyncStatus {
    case unknown
    case notDetermined
    case requesting
    case requestFailed
    case denied
    case granted
}
