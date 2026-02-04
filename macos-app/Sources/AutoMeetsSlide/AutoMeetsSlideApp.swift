import SwiftUI

@main
struct AutoMeetsSlideApp: App {
    init() {
        Task {
            await NotificationManager.shared.requestPermission()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 500, height: 600)
    }
}
