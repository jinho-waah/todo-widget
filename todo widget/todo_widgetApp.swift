import SwiftData
import SwiftUI

@main
struct todo_widgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = TodoModelContainerFactory.make()

    var body: some Scene {
        WindowGroup {
            TodoListView()
        }
        .modelContainer(sharedModelContainer)
        // .windowResizability(.contentSize) 제거 → 윈도우 크기는 AppDelegate 가
        // SwiftUI body 의 intrinsic height 통지를 받아 직접 setFrame 으로 driving.
        .defaultSize(width: DesignTokens.widgetWidth, height: 1)
    }
}
