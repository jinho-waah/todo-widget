import SwiftUI

private struct TodoDisplayContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TodoRowDisplayContent: View {
    let title: String
    let todoDescription: String?
    let dueDate: Date?
    let isCompleted: Bool
    let reminderAccentColor: Color

    @State private var displayContentHeight: CGFloat = 0

    private var displayTitle: String {
        title.isEmpty ? "새 할일" : title
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            reminderAccentBar

            VStack(alignment: .leading, spacing: 0) {
                titleText
                descriptionText
                dueDateDisplay
            }
            .background(contentHeightReader)
        }
        .onPreferenceChange(TodoDisplayContentHeightKey.self, perform: updateContentHeight)
    }

    private var titleText: some View {
        Text(displayTitle)
            .font(DesignTokens.todoTitleFont)
            .foregroundStyle(isCompleted ? DesignTokens.textCompleted : DesignTokens.textPrimary)
            .tracking(-0.1)
            .strikethrough(isCompleted)
    }

    @ViewBuilder
    private var descriptionText: some View {
        if let todoDescription, !todoDescription.isEmpty {
            Text(todoDescription)
                .font(DesignTokens.descFont)
                .foregroundStyle(isCompleted ? DesignTokens.textCompleted : DesignTokens.textSecondary)
                .strikethrough(isCompleted)
                .padding(.top, 3)
                .transition(contentTransition)
        }
    }

    @ViewBuilder
    private var dueDateDisplay: some View {
        if let dueDate {
            TodoDueDateDisplay(dueDate: dueDate, isCompleted: isCompleted)
                .transition(contentTransition)
        }
    }

    private var reminderAccentBar: some View {
        let baseline: CGFloat = 18
        let resolvedHeight = displayContentHeight > 0 ? max(displayContentHeight - 4, baseline) : baseline

        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(reminderAccentColor.opacity(isCompleted ? 0.45 : 0.95))
            .frame(width: 3, height: resolvedHeight)
            .padding(.top, 2)
            .animation(DesignTokens.toggleSpring, value: isCompleted)
    }

    private var contentHeightReader: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: TodoDisplayContentHeightKey.self,
                value: geometry.size.height
            )
        }
    }

    private var contentTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .move(edge: .top))
        )
    }

    private func updateContentHeight(_ newValue: CGFloat) {
        guard displayContentHeight != newValue else { return }
        displayContentHeight = newValue
    }
}
