import SwiftUI

@MainActor
@Observable
final class HeaderStore {
    struct State {
        var widgetTitle: String
        var isEditingTitle = false
        var draftTitle = ""
        var isTitleEditButtonHovered = false
        var hoveredHeaderButton: String?
    }

    enum Intent {
        case beginEditingTitle
        case updateDraftTitle(String)
        case commitTitle
        case titleEditButtonHovered(Bool)
        case headerButtonHovered(icon: String, hovering: Bool)
    }

    var state: State

    init(defaults: UserDefaults = .standard) {
        let storedTitle = defaults.string(forKey: "widgetTitle") ?? "Today"
        self.state = State(widgetTitle: storedTitle)
    }

    func send(_ intent: Intent) {
        switch intent {
        case .beginEditingTitle:
            state.draftTitle = state.widgetTitle
            state.isEditingTitle = true

        case .updateDraftTitle(let title):
            state.draftTitle = title

        case .commitTitle:
            let trimmed = state.draftTitle.trimmingCharacters(in: .whitespaces)
            state.widgetTitle = trimmed.isEmpty ? "Today" : trimmed
            UserDefaults.standard.set(state.widgetTitle, forKey: "widgetTitle")
            state.isEditingTitle = false

        case .titleEditButtonHovered(let hovering):
            withAnimation(.easeOut(duration: 0.15)) {
                state.isTitleEditButtonHovered = hovering
            }

        case .headerButtonHovered(let icon, let hovering):
            state.hoveredHeaderButton = hovering ? icon : nil
        }
    }
}
