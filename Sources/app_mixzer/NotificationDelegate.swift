import Foundation
@preconcurrency import UserNotifications
#if canImport(AppKit)
import AppKit
#endif

public final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    @MainActor public static let shared = NotificationDelegate()

    public override init() { super.init() }

    // When user interacts with the notification (taps it), reveal the exported file if provided
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let path = userInfo["filePath"] as? String {
            let url = URL(fileURLWithPath: path)
            #if canImport(AppKit)
            DispatchQueue.main.async {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            #endif
        }
        completionHandler()
    }

    // Show notifications when app is foregrounded as well
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
