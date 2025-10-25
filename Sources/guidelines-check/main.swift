import Foundation
import Yams

struct CheckResult {
    var problems: Int = 0
}

func fail(_ message: String) -> Never {
    print(message)
    exit(1)
}

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let docURL = cwd.appendingPathComponent("docs/guidelines.yml")

guard fm.fileExists(atPath: docURL.path) else {
    fail("docs/guidelines.yml not found at: \(docURL.path)")
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
