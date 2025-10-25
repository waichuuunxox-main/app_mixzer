import Foundation
import SwiftUI
import Yams

/// A small utility that mirrors the behaviour of
/// scripts/check_guidelines_consistency.py but in Swift.
public enum DocsConsistencyChecker {
    /// Check the YAML file at the given URL and return an array of textual problems.
    /// Mirrors python script outputs such as:
    /// - [FORMAT] key: expected mapping with 'zh' and 'en' keys
    /// - [MISSING] key: zh or en missing
    /// - [EMPTY] key: zh or en is empty
    /// - [LENGTH MISMATCH] key: zh len=..., en len=...
    public static func check(fileURL: URL) throws -> [String] {
        var problems: [String] = []

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            problems.append("docs/guidelines.yml not found")
            return problems
        }

        let text = try String(contentsOf: fileURL, encoding: .utf8)

        // decode into [String: [String: String]] to match expected structure
        let decoder = YAMLDecoder()
        let decoded: [String: [String: String]]
        do {
            decoded = try decoder.decode([String: [String: String]].self, from: text)
        } catch {
            problems.append("[PARSE] YAML decode error: \(error)")
            return problems
        }

        for (key, val) in decoded {
            guard let map = val as [String: String]? else {
                problems.append("[FORMAT] \(key): expected mapping with 'zh' and 'en' keys")
                continue
            }
            let zh = map["zh"]
            let en = map["en"]
            if zh == nil || en == nil {
                problems.append("[MISSING] \(key): zh or en missing")
                continue
            }
            if zh!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || en!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                problems.append("[EMPTY] \(key): zh or en is empty")
            }
            if abs(zh!.count - en!.count) > 300 {
                problems.append("[LENGTH MISMATCH] \(key): zh len=\(zh!.count), en len=\(en!.count)")
            }
        }

        if problems.isEmpty {
            problems.append("OK: guidelines consistency checks passed")
        }
        return problems
    }
}

// MARK: - SwiftUI View

public struct DocsConsistencyCheckerView: View {
    @State private var path: String = "docs/guidelines.yml"
    @State private var problems: [String] = []

    public init() {}

    public var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                HStack {
                    TextField("Path to guidelines.yml", text: $path)
                        .textFieldStyle(.roundedBorder)
                    Button("Check") {
                        runCheck()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding()

                List {
                    if problems.isEmpty {
                        Text("No problems detected").foregroundColor(.green)
                    } else {
                        ForEach(problems, id: \.self) { p in
                            Text(p).foregroundColor(p.hasPrefix("OK:") ? .green : .red)
                        }
                    }
                }
            }
            .navigationTitle("Guidelines Consistency")
        }
        .onAppear(perform: runCheck)
    }

    private func runCheck() {
        // Resolve relative to current working directory
        let cwd = FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: cwd))
        do {
            let result = try DocsConsistencyChecker.check(fileURL: url)
            self.problems = result
        } catch {
            self.problems = ["Failed to load guidelines: \(error)"]
        }
    }
}

// Preview for SwiftUI canvas
#if DEBUG
struct DocsConsistencyCheckerView_Previews: PreviewProvider {
    static var previews: some View {
        DocsConsistencyCheckerView()
    }
}
#endif
