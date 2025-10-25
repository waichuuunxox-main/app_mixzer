import Foundation
import SwiftUI
import Yams

public struct GuidelineEntry: Identifiable, Codable {
    // make id mutable so decoding doesn't warn about an immutable property with a default value
    public var id = UUID()
    public let zh: String
    public let en: String
}

public struct Guidelines: Codable {
    public let ui_ux: GuidelineEntry?
    public let animation: GuidelineEntry?
    public let routing: GuidelineEntry?
    public let state_management: GuidelineEntry?
    public let components: GuidelineEntry?
    public let data_api: GuidelineEntry?
    public let i18n: GuidelineEntry?
    public let testing: GuidelineEntry?
    public let performance: GuidelineEntry?
    public let deployment: GuidelineEntry?
}

public enum GuidelinesError: Error {
    case resourceNotFound
    case parseError(Error)
}

@MainActor
public final class GuidelinesLoader: ObservableObject {
    @Published public private(set) var guidelinesDict: [String: (zh: String, en: String)] = [:]
    @Published public private(set) var problems: [String] = []

    public init() {
        // empty
    }

    public func loadFromBundle() throws {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "guidelines", withExtension: "yml") else {
            throw GuidelinesError.resourceNotFound
        }
        try load(from: url)
    }

    public func load(from url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        do {
            let decoder = YAMLDecoder()
            let dict = try decoder.decode([String: [String: String]].self, from: text)
            var tmp: [String: (zh: String, en: String)] = [:]
            var problemsFound: [String] = []
            for (key, val) in dict {
                let zh = val["zh"] ?? ""
                let en = val["en"] ?? ""
                tmp[key] = (zh: zh, en: en)
                if zh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || en.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    problemsFound.append("EMPTY: \(key)")
                }
                if abs(zh.count - en.count) > 300 {
                    problemsFound.append("LENGTH_MISMATCH: \(key)")
                }
            }
            self.guidelinesDict = tmp
            self.problems = problemsFound
        } catch {
            throw GuidelinesError.parseError(error)
        }
    }

    /// Public helper to report errors from callers that can't write to `problems` directly.
    public func reportError(_ message: String) {
        self.problems = [message]
    }
}

public struct GuidelinesCheckerView: View {
    @StateObject private var loader = GuidelinesLoader()

    public init() {}

    public var body: some View {
        NavigationView {
            List {
                Section(header: Text("Problems")) {
                    if loader.problems.isEmpty {
                        Text("No problems detected").foregroundColor(.green)
                    } else {
                        ForEach(loader.problems, id: \.self) { p in
                            Text(p).foregroundColor(.red)
                        }
                    }
                }
                Section(header: Text("Guidelines")) {
                    ForEach(Array(loader.guidelinesDict.keys).sorted(), id: \.self) { key in
                        if let pair = loader.guidelinesDict[key] {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(key).font(.headline)
                                Text("ZH: \(pair.zh)").font(.subheadline)
                                Text("EN: \(pair.en)").font(.subheadline)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.sidebar)
            #endif
            .navigationTitle("Guidelines Checker")
            .onAppear {
                do {
                    try loader.loadFromBundle()
                } catch {
                    // use the public helper to report errors since `problems` has a private setter
                    loader.reportError("Failed to load guidelines: \(error)")
                }
            }
        }
    }
}
