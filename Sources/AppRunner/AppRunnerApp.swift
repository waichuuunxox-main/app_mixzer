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
                    let msg = "DEBUG: AppRunner startup -> loaded ranking items count: \(items.count)\n"
                    // Ensure logs directory exists
                    let fm = FileManager.default
                    let logsDir = fm.currentDirectoryPath + "/logs"
                    try? fm.createDirectory(atPath: logsDir, withIntermediateDirectories: true)
                    let logFile = logsDir + "/apprunner_debug.log"
                    if let data = msg.data(using: .utf8) {
                        if fm.fileExists(atPath: logFile) {
                            if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logFile)) {
                                defer {
                                    do { try handle.close() } catch { }
                                }
                                do {
                                    try handle.seekToEnd()
                                } catch { }
                                do {
                                    try handle.write(contentsOf: data)
                                } catch { }
                            }
                        } else {
                            fm.createFile(atPath: logFile, contents: data)
                        }
                    }
                }
        }
    }
}
