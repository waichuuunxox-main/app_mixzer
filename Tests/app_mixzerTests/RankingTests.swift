import XCTest
@testable import app_mixzer

final class RankingTests: XCTestCase {
    func testKworbJSONDecoding() throws {
        let cwd = FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: cwd).appendingPathComponent("docs/kworb_top10.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let arr = try decoder.decode([KworbEntry].self, from: data)
        XCTAssertEqual(arr.count, 10)
        XCTAssertEqual(arr.first?.rank, 1)
    }

    func testITunesParsingMock() async throws {
        // prepare a mock session with known JSON
        struct MockSession: URLSessionProtocol {
            let data: Data
            func data(from url: URL) async throws -> (Data, URLResponse) {
                return (data, URLResponse())
            }
        }

        // minimal iTunes JSON
        let json = "{ \"resultCount\":1, \"results\":[{ \"trackName\": \"X\", \"artistName\": \"Y\", \"artworkUrl100\": \"https://example.com/a.jpg\", \"previewUrl\": \"https://example.com/p.mp3\", \"releaseDate\": \"2020-01-01T00:00:00Z\" }] }"
        let mock = MockSession(data: Data(json.utf8))
        let svc = RankingService(session: mock)
        let kworb = KworbEntry(rank: 1, title: "X", artist: "Y")
        let track = try await svc.queryITunes(for: kworb)
        XCTAssertEqual(track.trackName, "X")
        XCTAssertEqual(track.artistName, "Y")
        XCTAssertEqual(track.artworkUrl100, "https://example.com/a.jpg")
    }
}
