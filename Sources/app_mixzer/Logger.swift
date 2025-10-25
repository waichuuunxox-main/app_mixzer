import Foundation

public enum SimpleLogger {
    // Enable debug logging by setting environment variable APP_MIXZER_DEBUG=1
    static var isDebug: Bool {
        return ProcessInfo.processInfo.environment["APP_MIXZER_DEBUG"] == "1"
    }

    public static func log(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(message)\n"

        // Write to stdout/stderr when debug enabled
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
        } catch {
            // If logging to file fails, still no-op silently to avoid crashing the app
        }
    }
}
