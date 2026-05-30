import SwiftUI

struct TodoDueDateDisplay: View {
    let dueDate: Date
    let isCompleted: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.system(size: 10, weight: .regular))

            Text(displayInfo.text)
                .font(displayInfo.font)
                .tracking(-0.05)
        }
        .foregroundStyle(displayInfo.color)
        .padding(.top, 4)
    }

    private var displayInfo: (text: String, color: Color, font: Font) {
        if isCompleted {
            return (formattedDueDate(overdue: false), DesignTokens.textMetaCompleted, DesignTokens.dateFont)
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(dueDate) {
            return (formattedDueDate(overdue: false), DesignTokens.systemBlue, DesignTokens.dateFontEmphasized)
        }
        if dueDate < calendar.startOfDay(for: Date()) {
            return (formattedDueDate(overdue: true), DesignTokens.systemRed, DesignTokens.dateFontEmphasized)
        }
        return (formattedDueDate(overdue: false), DesignTokens.textMeta, DesignTokens.dateFont)
    }

    private func formattedDueDate(overdue: Bool) -> String {
        let calendar = Calendar.current

        var text: String
        if calendar.isDateInToday(dueDate) {
            text = relativeDayString(daysFromToday: 0)
        } else if calendar.isDateInTomorrow(dueDate) {
            text = relativeDayString(daysFromToday: 1)
        } else if calendar.isDateInYesterday(dueDate) {
            text = relativeDayString(daysFromToday: -1)
        } else {
            text = formattedDate(dueDate)
        }

        if let time = timeString(dueDate) {
            text += ", \(time)"
        }
        if overdue {
            text += overdueSuffix()
        }
        return text
    }

    private func relativeDayString(daysFromToday days: Int) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        formatter.locale = .userPreferred
        return formatter.localizedString(from: DateComponents(day: days))
    }

    private func overdueSuffix() -> String {
        let code = Locale.userPreferred.language.languageCode?.identifier
        switch code {
        case "ko": return " 지남"
        default: return " overdue"
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        return DateFormatters.formatter(sameYear: sameYear).string(from: date)
    }

    private func timeString(_ date: Date) -> String? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard components.hour != 0 || components.minute != 0 else { return nil }
        return date.formatted(.dateTime.hour().minute().locale(.userPreferred))
    }
}
