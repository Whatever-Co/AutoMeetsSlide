import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up notification delegate early
        NotificationManager.shared.setup()

        Task {
            await NotificationManager.shared.requestPermission()
        }

        FolderWatcherService.shared.startWatching()
    }
}

@main
struct AutoMeetsSlideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 500, height: 600)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Logout") {
                    AppState.shared.logout()
                }
                .keyboardShortcut("L", modifiers: [.command, .shift])
                .disabled(AppState.shared.isAuthenticated != true)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
