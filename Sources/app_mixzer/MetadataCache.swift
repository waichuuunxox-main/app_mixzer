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
    
    // Persist debounce task to avoid frequent disk writes when many sets happen in quick succession.
    private var persistTask: Task<Void, Never>? = nil

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
        // Debounce persistent writes: schedule a write 1s after the last set
        persistTask?.cancel()
        persistTask = Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
            await self?.performPersist()
        }
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(store)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func performPersist() async {
        do {
            try persist()
        } catch {
            // best-effort: log but do not throw
            SimpleLogger.log("Failed to persist MetadataCache: \(error)")
        }
    }

    static func normalizeKey(title: String, artist: String) -> String {
        return "\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())::\(artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }
}
