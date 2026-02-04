import Foundation
import UserNotifications

@MainActor
class NotificationManager {
    static let shared = NotificationManager()

    private init() {}

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.general.error("Notification permission error: \(error)")
        }
    }

    func notifyCompletion(fileName: String, outputPath: String) {
        let content = UNMutableNotificationContent()
        content.title = "PDF Complete"
        content.body = "\(fileName) has been converted"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func notifyError(fileName: String, error: String) {
        let content = UNMutableNotificationContent()
        content.title = "PDF Failed"
        content.body = "\(fileName): \(error)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
