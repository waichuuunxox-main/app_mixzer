import Foundation

/// Persistent actor-backed metadata cache for iTunes query results.
/// Keeps in-memory cache with TTL and persists to disk as JSON to avoid re-querying across launches.
public actor MetadataCache {
    public static let shared = MetadataCache()

    public struct CacheEntry: Codable {
        public let track: ITunesTrack
        public let inserted: Date
    }

    private var store: [String: CacheEntry] = [:]
    private let ttl: TimeInterval
    private let fileURL: URL

    public init(ttl: TimeInterval = 24 * 60 * 60, filename: String = "app_mixzer_metadata_cache.json") {
        self.ttl = ttl
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        self.fileURL = caches.appendingPathComponent(filename)
        // Try to load persisted cache
        if let data = try? Data(contentsOf: fileURL) {
            if let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) {
                self.store = decoded
            }
        }
    }

    public func get(forTitle title: String, artist: String) -> ITunesTrack? {
        let key = MetadataCache.normalizeKey(title: title, artist: artist)
        guard let entry = store[key] else { return nil }
        if Date().timeIntervalSince(entry.inserted) > ttl {
            store.removeValue(forKey: key)
            try? persist() // best-effort
            return nil
        }
        return entry.track
    }

    public func set(_ track: ITunesTrack, forTitle title: String, artist: String) {
        let key = MetadataCache.normalizeKey(title: title, artist: artist)
        let entry = CacheEntry(track: track, inserted: Date())
        store[key] = entry
        try? persist()
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(store)
        try data.write(to: fileURL, options: [.atomic])
    }

    static func normalizeKey(title: String, artist: String) -> String {
        return "\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())::\(artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }
}
