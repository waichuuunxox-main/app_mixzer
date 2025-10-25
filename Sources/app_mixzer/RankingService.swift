// 根據 MusicRankingLogic.md 的邏輯設計
// 資料來源: Kworb (本地 JSON kworb_top10.json) + iTunes Search API
// - Kworb 提供排行榜（前 10 名的 title + artist）
// - 使用 iTunes Search API 擷取歌曲細節（封面、preview、發行資訊）
// 資料流程: loadLocalKworb() -> queryITunes(for:) -> loadRanking() (整合)
// 注意: 本模組不會播放音樂，只顯示與整合公開來源資料；不要加入任何需 API key 的私有服務
import Foundation

// Abstraction for URLSession to allow mocking in tests
public protocol URLSessionProtocol {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

public enum RankingError: Error {
    case fileNotFound
    case parseError(Error)
    case networkError(Error)
    case noResults
}

public final class RankingService: @unchecked Sendable {
    public private(set) var session: URLSessionProtocol

    public init(session: URLSessionProtocol = URLSession.shared) {
        self.session = session
    }

    /// Load local kworb-like JSON from docs/kworb_top10.json relative to CWD
    /// Load local kworb-like JSON from docs/kworb_top10.json relative to CWD
    ///
    /// Contract:
    /// - Inputs: none
    /// - Outputs: an array of `KworbEntry` parsed from a kworb_top10.json file.
    /// - Errors:
    ///   - `RankingError.fileNotFound` if no candidate file is found
    ///   - `RankingError.parseError` if JSON decoding fails for a found file
    /// - Notes / Edge cases:
    ///   - The method searches several candidate locations (cwd/docs, executable nearby, parent dirs,
    ///     bundle resource paths, and discovered `.bundle` directories) to make execution robust
    ///     when the binary is launched from Xcode or other working directories.
    ///   - This function is async because it may perform file system checks; it does not perform network I/O.
    public func loadLocalKworb() async throws -> [KworbEntry] {
        // Try multiple likely locations for the kworb file so the executable
        // can be launched from different working directories (Xcode, Terminal, double-clicked binary).
        func candidateURLs() -> [URL] {
            var urls: [URL] = []

            // 1) cwd/docs/kworb_top10.json
            let cwd = FileManager.default.currentDirectoryPath
            urls.append(URL(fileURLWithPath: cwd).appendingPathComponent("docs/kworb_top10.json"))

            // 2) executable's directory and nearby paths
            let execPath = CommandLine.arguments.first ?? ""
            if !execPath.isEmpty {
                let execURL = URL(fileURLWithPath: execPath).deletingLastPathComponent()
                urls.append(execURL.appendingPathComponent("docs/kworb_top10.json"))
                urls.append(execURL.deletingLastPathComponent().appendingPathComponent("docs/kworb_top10.json"))
            }

            // 3) search upwards from cwd for a docs/kworb_top10.json (limit depth)
            var dir = URL(fileURLWithPath: cwd)
            for _ in 0..<6 {
                urls.append(dir.appendingPathComponent("docs/kworb_top10.json"))
                guard let parent = dir.deletingLastPathComponent().path.isEmpty ? nil : dir.deletingLastPathComponent() as URL? else { break }
                // stop if root reached
                if parent.path == dir.path { break }
                dir = parent
            }

            // 4) Try Bundle.module if available (works when kworb file is added as a resource)
            #if canImport(Foundation)
            // Use Mirror of Bundle to avoid forcing a compile-time dependency on resources
            if let bundleURL = Bundle.main.resourceURL {
                urls.append(bundleURL.appendingPathComponent("kworb_top10.json"))
                urls.append(bundleURL.appendingPathComponent("docs/kworb_top10.json"))
            }
            #endif

            // 5) Search for any sibling or nearby .bundle directories (SPM places resources in <target>_<target>.bundle)
            if let execPath = CommandLine.arguments.first, !execPath.isEmpty {
                let execURL = URL(fileURLWithPath: execPath).deletingLastPathComponent()
                let searchDirs = [execURL, execURL.deletingLastPathComponent(), URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]
                for dir in searchDirs {
                    if let children = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                        for child in children where child.pathExtension == "bundle" {
                            urls.append(child.appendingPathComponent("kworb_top10.json"))
                            urls.append(child.appendingPathComponent("docs/kworb_top10.json"))
                        }
                    }
                }

                // Also search up to a couple of parent directories for any *.bundle in .build
                var probe = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                for _ in 0..<4 {
                    let buildDir = probe.appendingPathComponent(".build")
                    if let bundles = try? FileManager.default.contentsOfDirectory(at: buildDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                        for b in bundles where b.pathExtension == "bundle" {
                            urls.append(b.appendingPathComponent("kworb_top10.json"))
                        }
                    }
                    let parent = probe.deletingLastPathComponent()
                    if parent.path == probe.path { break }
                    probe = parent
                }
            }

            return urls
        }

        let decoder = JSONDecoder()
        for candidate in candidateURLs() {
            if FileManager.default.fileExists(atPath: candidate.path) {
                do {
                    let data = try Data(contentsOf: candidate)
                        // Decode into the concrete KworbEntry array; decoder errors will be wrapped
                        // as RankingError.parseError so callers can distinguish parse vs missing file.
                        let entries = try decoder.decode([KworbEntry].self, from: data)
                    // Temporary debug: write which file was used and how many entries were parsed
                    SimpleLogger.log("DEBUG: loadLocalKworb -> loaded \(entries.count) entries from: \(candidate.path)")
                    return entries
                } catch {
                    throw RankingError.parseError(error)
                }
            }
        }

        throw RankingError.fileNotFound
    }

    /// Query iTunes API for a given song title and artist (returns first matched track)
    /// Query iTunes API for a given song title and artist (returns first matched track)
    ///
    /// Contract:
    /// - Inputs: a `KworbEntry` (rank, title, artist)
    /// - Outputs: the first `ITunesTrack` matching the search term
    /// - Errors:
    ///   - `RankingError.noResults` when the iTunes search returns zero results
    ///   - `RankingError.networkError` wrapping network or decoding failures
    /// - Notes / Edge cases:
    ///   - This method performs a network call to the public iTunes Search API and is subject to
    ///     network latency and rate limiting. Callers should handle transient failures gracefully
    ///     (e.g., retry, fallback to minimal metadata).
    ///   - The search term is a simple concatenation of title + artist to increase match quality.
    public func queryITunes(for entry: KworbEntry) async throws -> ITunesTrack {
        // Check metadata cache first
        if let cached = await MetadataCache.shared.get(forTitle: entry.title, artist: entry.artist) {
            return cached
        }

        let term = "\(entry.title) \(entry.artist)"
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw RankingError.noResults
        }
        let urlString = "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=1"
        guard let url = URL(string: urlString) else { throw RankingError.noResults }

        var lastError: Error?
        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await session.data(from: url)
                // If we have an HTTP response, inspect status code for retry decisions
                if let http = response as? HTTPURLResponse {
                    if (400...499).contains(http.statusCode) {
                        // Client errors are not transient — don't retry
                        let decoder = JSONDecoder()
                        let resp = try decoder.decode(ITunesSearchResponse.self, from: data)
                        if let track = resp.results.first {
                            await MetadataCache.shared.set(track, forTitle: entry.title, artist: entry.artist)
                            return track
                        }
                        throw RankingError.noResults
                    }
                    // For 5xx we will treat as transient and allow retry below
                }

                let decoder = JSONDecoder()
                let resp = try decoder.decode(ITunesSearchResponse.self, from: data)
                if let track = resp.results.first {
                    // store in cache for future reuse
                    await MetadataCache.shared.set(track, forTitle: entry.title, artist: entry.artist)
                    return track
                } else {
                    throw RankingError.noResults
                }
            } catch {
                lastError = error
                // If it's a definitive noResults, don't retry
                if let r = error as? RankingError {
                    switch r {
                    case .noResults:
                        break
                    default:
                        break
                    }
                }

                // Decide whether to retry: if network error or 5xx response
                var shouldRetry = false
                if error is URLError {
                    shouldRetry = true
                } else if error is DecodingError {
                    // decoding errors likely not transient; do not retry
                    shouldRetry = false
                } else {
                    // fallback: allow retry unless we can tell it's client error
                    shouldRetry = true
                }

                if !shouldRetry { break }

                // Exponential backoff before retrying
                if attempt < maxAttempts {
                    let backoffSeconds = pow(2.0, Double(attempt - 1)) * 0.5
                    try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                    continue
                }
            }
        }

        throw RankingError.networkError(lastError ?? URLError(.unknown))
    }

    /// High-level: load local ranking and enrich via iTunes API
    /// High-level: load local ranking and enrich via iTunes API
    ///
    /// Contract:
    /// - Inputs: none
    /// - Outputs: an array of `RankingItem` representing the combined data from kworb + iTunes
    /// - Behavior:
    ///   - Attempts to load Kworb entries using `loadLocalKworb()` (throws on missing file / parse errors)
    ///   - For each Kworb entry, attempts to query iTunes; if enrichment succeeds, the returned
    ///     `ITunesTrack` is converted to `RankingItem`, otherwise a fallback `RankingItem` with
    ///     minimal data is created.
    /// - Notes / Edge cases:
    ///   - The function returns an empty array if Kworb cannot be loaded. It never throws to
    ///     simplify caller handling in UI code; errors are logged via `SimpleLogger`.
    public func loadRanking() async -> [RankingItem] {
        // Backwards-compatible default: call the new API with defaults.
        return await loadRanking(remoteURL: nil, maxConcurrency: 6, topN: nil)
    }

    /// Attempt to download a remote kworb-like JSON file from the given URL.
    /// Applies basic safety checks: HTTPS only, size limit, and JSON decoding into [KworbEntry].
    public func loadRemoteKworb(from url: URL, timeout: TimeInterval = 12, maxBytes: Int = 2_000_000) async throws -> [KworbEntry] {
        // Only allow HTTPS
        guard url.scheme?.lowercased() == "https" else { throw RankingError.networkError(NSError(domain: "RankingService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Only HTTPS URLs are allowed"])) }

        do {
            let (data, _) = try await session.data(from: url)
            if data.count > maxBytes {
                throw RankingError.parseError(NSError(domain: "RankingService", code: 413, userInfo: [NSLocalizedDescriptionKey: "Remote file too large"]))
            }
            let decoder = JSONDecoder()
            let entries = try decoder.decode([KworbEntry].self, from: data)
            SimpleLogger.log("DEBUG: loadRemoteKworb -> loaded \(entries.count) entries from: \(url.absoluteString)")
            return entries
        } catch let err as RankingError {
            throw err
        } catch {
            throw RankingError.networkError(error)
        }
    }

    /// High-level loader that supports remote kworb, controlled concurrency for enrichment, and incremental progress callbacks.
    /// - Parameters:
    ///   - remoteURL: optional remote kworb URL to try first (falls back to local on failure)
    ///   - maxConcurrency: number of concurrent iTunes queries
    ///   - topN: optional cap for number of entries to load
    ///   - progress: called each time an individual RankingItem is ready (main-thread expected for UI updates)
    public func loadRanking(remoteURL: URL? = nil, maxConcurrency: Int = 6, topN: Int? = nil) async -> [RankingItem] {
        var entries: [KworbEntry] = []
        do {
            if let r = remoteURL {
                do {
                    entries = try await loadRemoteKworb(from: r)
                } catch {
                    SimpleLogger.log("Failed to load remote kworb (falling back to local): \(error)")
                    entries = try await loadLocalKworb()
                }
            } else {
                entries = try await loadLocalKworb()
            }
        } catch {
            SimpleLogger.log("Failed to load kworb: \(error)")
            return []
        }

        if let cap = topN, entries.count > cap {
            entries = Array(entries.prefix(cap))
        }

        // Start with minimal items so UI can render a skeleton immediately.
        var results: [RankingItem] = entries.map { entry in
            RankingItem(rank: entry.rank,
                        title: entry.title,
                        artist: entry.artist,
                        artworkURL: nil,
                        previewURL: nil,
                        releaseDate: nil,
                        collectionName: nil)
        }

        // Process in batches to control concurrency and provide incremental updates.
        let batchSize = max(1, maxConcurrency)
        let chunks = stride(from: 0, to: entries.count, by: batchSize).map { Array(entries[$0..<min($0 + batchSize, entries.count)]) }

        for chunk in chunks {
            await withTaskGroup(of: (Int, RankingItem?).self) { group in
                for entry in chunk {
                    group.addTask {
                        do {
                            let track = try await self.queryITunes(for: entry)
                            let item = track.toRankingItem(from: entry)
                            return (entry.rank, item)
                        } catch {
                            // fallback minimal item
                            let fallback = RankingItem(rank: entry.rank,
                                                       title: entry.title,
                                                       artist: entry.artist,
                                                       artworkURL: nil,
                                                       previewURL: nil,
                                                       releaseDate: nil,
                                                       collectionName: nil)
                            return (entry.rank, fallback)
                        }
                    }
                }

                for await (rank, maybeItem) in group {
                    if let item = maybeItem {
                        if let idx = results.firstIndex(where: { $0.rank == rank }) {
                            results[idx] = item
                            // Broadcast enrichment of a single item so UI can update incrementally
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name: .appMixzerDidEnrichItem, object: item)
                            }
                        }
                    }
                }
            }
        }

        return results.sorted { $0.rank < $1.rank }
    }
}
