import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

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
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 500, height: 600)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    appDelegate.updaterController.checkForUpdates(nil)
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Files...") {
                    AppState.shared.selectFilesForSettingsSheet()
                }
                .keyboardShortcut("O", modifiers: .command)
                .disabled(AppState.shared.isAuthenticated != true)
            }
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
