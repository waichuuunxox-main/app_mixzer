import Foundation
@preconcurrency import UserNotifications

actor NotificationHelper {
    static let shared = NotificationHelper()

    init() {}

    nonisolated func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus != .authorized else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in
                // best-effort
            }
        }
    }

    func postExportNotification(fileURL: URL) {
        requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = "AppMixzer — Export Complete"
        content.body = "Exported CSV to: \(fileURL.lastPathComponent)"
        // include file path so delegate can reveal it when the notification is tapped
        content.userInfo = ["filePath": fileURL.path]
        content.sound = .default
        let id = "appmixzer.export.\(Int(Date().timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
