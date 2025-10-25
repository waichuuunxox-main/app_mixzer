import SwiftUI
import app_mixzer
@preconcurrency import UserNotifications

@main
struct AppRunnerApp: App {
    init() {
        // register notification delegate early so notification actions can be handled
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }
    var body: some Scene {
        WindowGroup("AppRunner") {
            RankingsView()
                .task {
                    // Temporary startup check: attempt to load ranking and write result to a log file for debug
                    let svc = RankingService()
                    let items = await svc.loadRanking()
                    SimpleLogger.log("DEBUG: AppRunner startup -> loaded ranking items count: \(items.count)")
                }
        }
    }
}
