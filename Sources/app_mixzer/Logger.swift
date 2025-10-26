import Foundation

import Foundation

public enum SimpleLogger {
    // User-default key for toggling debug at runtime
    static let userDebugKey = "APP_MIXZER_DEBUG_USER"

    // Enable debug logging by environment variable or user-default toggle
    static var isDebug: Bool {
        let env = ProcessInfo.processInfo.environment["APP_MIXZER_DEBUG"] == "1"
        let user = UserDefaults.standard.bool(forKey: userDebugKey)
        return env || user
    }

    // Allow toggling debug via runtime settings (persisted)
    public static func setDebugEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: userDebugKey)
    }

    public static func log(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(message)\n"

        // Write to stderr when debug enabled
        if isDebug {
            FileHandle.standardError.write((line.data(using: .utf8) ?? Data()))
        }

        // Ensure logs directory exists relative to CWD
        let fm = FileManager.default
        let logsDir = fm.currentDirectoryPath + "/logs"
        do {
            try fm.createDirectory(atPath: logsDir, withIntermediateDirectories: true)
            let logFile = logsDir + "/apprunner.log"
            if let data = line.data(using: .utf8) {
                if fm.fileExists(atPath: logFile) {
                    if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logFile)) {
                        defer {
                            do { try handle.close() } catch { }
                        }
                        do { try handle.seekToEnd() } catch { }
                        do { try handle.write(contentsOf: data) } catch { }
                    }
                } else {
                    fm.createFile(atPath: logFile, contents: data)
                }
            }
            // Mirror to user logs so Finder/Dock 啟動時也能找到日志
            let userLogsDir = (fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/app_mixzer").path)
            try fm.createDirectory(atPath: userLogsDir, withIntermediateDirectories: true)
            let userLogFile = userLogsDir + "/apprunner.log"
            if let data = line.data(using: .utf8) {
                if fm.fileExists(atPath: userLogFile) {
                    if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: userLogFile)) {
                        defer { do { try handle.close() } catch { } }
                        do { try handle.seekToEnd() } catch { }
                        do { try handle.write(contentsOf: data) } catch { }
                    }
                } else {
                    fm.createFile(atPath: userLogFile, contents: data)
                }
            }
        } catch {
            // If logging to file fails, still no-op silently to avoid crashing the app
        }
    }
}
