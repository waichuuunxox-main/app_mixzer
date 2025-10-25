import XCTest
@testable import app_mixzer

final class MockSession: URLSessionProtocol {
    let responses: [URL: (Data, URLResponse)]
    init(responses: [URL: (Data, URLResponse)]) { self.responses = responses }
    func data(from url: URL) async throws -> (Data, URLResponse) {
        if let r = responses[url] { return r }
        throw URLError(.badServerResponse)
    }
}

final class RankingServiceTests: XCTestCase {
    func testLoadRemoteKworbSuccess() async throws {
        let json = "[{\"rank\":1,\"title\":\"Song A\",\"artist\":\"Artist A\"}]"
        let url = URL(string: "https://example.com/kworb.json")!
        let data = json.data(using: .utf8)!
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let svc = RankingService(session: MockSession(responses: [url: (data, resp)]))
        let entries = try await svc.loadRemoteKworb(from: url)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].title, "Song A")
    }

    func testLoadRemoteKworbRejectsHTTP() async throws {
        let url = URL(string: "http://example.com/kworb.json")!
        let svc = RankingService()
        do {
            _ = try await svc.loadRemoteKworb(from: url)
            XCTFail("Should throw for non-HTTPS")
        } catch {
            // expected
        }
    }
}
