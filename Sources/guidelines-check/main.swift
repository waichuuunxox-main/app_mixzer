import Foundation
import Yams

struct CheckResult {
    var problems: Int = 0
}

func fail(_ message: String) -> Never {
    print(message)
    exit(1)
}

let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

// Helper: search for docs/guidelines.yml in current dir and parent folders
func findGuidelinesInParents(startingAt url: URL) -> URL? {
    var current = url
    let fm = FileManager.default
    while true {
        let candidate = current.appendingPathComponent("docs/guidelines.yml")
        if fm.fileExists(atPath: candidate.path) {
            return candidate
        }
        let parent = current.deletingLastPathComponent()
        if parent.path == current.path { break }
        current = parent
    }
    return nil
}

// Candidate 1: cwd/docs/guidelines.yml
var docURL: URL? = nil
if let found = findGuidelinesInParents(startingAt: cwd) {
    docURL = found
}

// Candidate 2: executable bundle (if resources were copied there)
if docURL == nil {
    let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    let candidate = execDir.appendingPathComponent("docs/guidelines.yml")
    if FileManager.default.fileExists(atPath: candidate.path) {
        docURL = candidate
    }
}

// Candidate 3: try Bundle.module if available (requires the target to include resources)
#if canImport(Foundation)
if docURL == nil {
    // Attempt to find resource inside the built bundle location
    if let bundleURL = Bundle.main.resourceURL {
        let candidate = bundleURL.appendingPathComponent("docs/guidelines.yml")
        if FileManager.default.fileExists(atPath: candidate.path) {
            docURL = candidate
        }
    }
}
#endif

guard let docURL = docURL else {
    fail("docs/guidelines.yml not found (looked in current dir and parent folders, executable dir, and bundle resources). Current working dir: \(cwd.path)")
}

do {
    let text = try String(contentsOf: docURL, encoding: .utf8)
    let decoder = YAMLDecoder()
    let dict = try decoder.decode([String: [String: String]].self, from: text)
    var result = CheckResult()

    for (key, val) in dict {
        guard let zh = val["zh"], let en = val["en"] else {
            print("[MISSING] \(key): zh or en missing")
            result.problems += 1
            continue
        }
        if zh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || en.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("[EMPTY] \(key): zh or en is empty")
            result.problems += 1
        }
        // Heuristic: length mismatch
        if abs(zh.count - en.count) > 300 {
            print("[LENGTH MISMATCH] \(key): zh len=\(zh.count), en len=\(en.count)")
            result.problems += 1
        }
    }

    if result.problems == 0 {
        print("OK: guidelines consistency checks passed")
        exit(0)
    } else {
        print("Found \(result.problems) problems")
        exit(1)
    }
} catch {
    fail("Error parsing guidelines.yml: \(error)")
}
