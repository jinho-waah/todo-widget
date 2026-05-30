import Foundation

enum RemindersDateMapper {
    static func dueDateComponents(from date: Date?) -> DateComponents? {
        guard let date else { return nil }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard components.hour != 0 || components.minute != 0 else {
            return calendar.dateComponents([.year, .month, .day], from: date)
        }
        return components
    }
}
