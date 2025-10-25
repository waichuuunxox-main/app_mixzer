import SwiftUI
import app_mixzer

@main
struct AppRunnerApp: App {
    var body: some Scene {
        WindowGroup("AppRunner") {
            RankingsView()
                .task {
                    // Temporary startup check: attempt to load ranking and print result for debug
                    let svc = RankingService()
                    let items = await svc.loadRanking()
                    print("DEBUG: AppRunner startup -> loaded ranking items count: \(items.count)")
                }
        }
    }
}
