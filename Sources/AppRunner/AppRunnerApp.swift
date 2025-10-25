import SwiftUI
import app_mixzer

@main
struct AppRunnerApp: App {
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
