import XCTest
@testable import app_mixzer

final class MetadataCacheTests: XCTestCase {
    func testCacheSetGetAndExpiry() async {
        let cache = MetadataCache(ttl: 1) // 1 second ttl
        let track = ITunesTrack(trackName: "t", artistName: "a", artworkUrl100: nil, previewUrl: nil, releaseDate: nil, collectionName: nil)
        await cache.set(track, forTitle: "t", artist: "a")
        let maybe = await cache.get(forTitle: "t", artist: "a")
        XCTAssertNotNil(maybe)
        // wait for expiry
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        let expired = await cache.get(forTitle: "t", artist: "a")
        XCTAssertNil(expired)
    }
}
