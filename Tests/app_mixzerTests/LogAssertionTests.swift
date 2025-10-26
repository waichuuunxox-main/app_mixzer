import XCTest
@testable import app_mixzer

@MainActor
final class LogAssertionTests: XCTestCase {
    final class MockRankingService: RankingServiceProtocol {
        var callCount = 0
        func loadLocalKworb() async throws -> [KworbEntry] { return [] }
        func loadRemoteKworb(from url: URL, timeout: TimeInterval, maxBytes: Int) async throws -> [KworbEntry] { return [] }
        func loadAppleRSSTopSongs(country: String, limit: Int) async throws -> [KworbEntry] { return [] }
        func loadRanking(remoteURL: URL?, maxConcurrency: Int, topN: Int?, initialEntries: [KworbEntry]?) async -> [RankingItem] {
            callCount += 1
            let this = callCount
            if this == 1 {
                // slow
                try? await Task.sleep(nanoseconds: 400 * 1_000_000)
                return (1...10).map { RankingItem(rank: $0, title: "Old\($0)", artist: "OldArtist", artworkURL: nil, previewURL: nil, releaseDate: nil, collectionName: nil) }
            } else {
                // fast
                try? await Task.sleep(nanoseconds: 50 * 1_000_000)
                return (1...100).map { RankingItem(rank: $0, title: "New\($0)", artist: "NewArtist", artworkURL: nil, previewURL: nil, releaseDate: nil, collectionName: nil) }
            }
        }
    }

    func testDiscardingFinalResultsLogged() async throws {
        // Ensure logging enabled and start with a clean log file
        SimpleLogger.setDebugEnabled(true)
        let fm = FileManager.default
        let logPath = fm.currentDirectoryPath + "/logs/apprunner.log"
        if fm.fileExists(atPath: logPath) {
            try? fm.removeItem(atPath: logPath)
        }

        let mock = MockRankingService()
        let vm = RankingsViewModel(service: mock)

        // Start slow first load
        let t1 = Task { await vm.load() }
        // Start second load shortly after
        try await Task.sleep(nanoseconds: 120 * 1_000_000)
        let t2 = Task { await vm.load() }

        await t1.value
        await t2.value

        // Give logger a moment to flush
        try? await Task.sleep(nanoseconds: 40 * 1_000_000)

        // Read the log file and assert the discarding message exists
        XCTAssertTrue(fm.fileExists(atPath: logPath), "Expected log file to exist")
        let data = try Data(contentsOf: URL(fileURLWithPath: logPath))
        let s = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("discarding final results"), "Expected logs to contain 'discarding final results' but got:\n\(s)" )
    }
}
