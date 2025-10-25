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
    public func queryITunes(for entry: KworbEntry) async throws -> ITunesTrack {
        let term = "\(entry.title) \(entry.artist)"
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw RankingError.noResults
        }
        let urlString = "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=1"
        guard let url = URL(string: urlString) else { throw RankingError.noResults }

        do {
            let (data, _) = try await session.data(from: url)
            let decoder = JSONDecoder()
            let resp = try decoder.decode(ITunesSearchResponse.self, from: data)
            if let track = resp.results.first {
                return track
            } else {
                throw RankingError.noResults
            }
        } catch {
            throw RankingError.networkError(error)
        }
    }

    /// High-level: load local ranking and enrich via iTunes API
    public func loadRanking() async -> [RankingItem] {
        var items: [RankingItem] = []
        do {
            let kworb = try await loadLocalKworb()
            for entry in kworb {
                do {
                    let track = try await queryITunes(for: entry)
                    let item = track.toRankingItem(from: entry)
                    items.append(item)
                } catch {
                    // If API fails for one item, skip but include a fallback item with minimal data
                    let fallback = RankingItem(rank: entry.rank,
                                               title: entry.title,
                                               artist: entry.artist,
                                               artworkURL: nil,
                                               previewURL: nil,
                                               releaseDate: nil,
                                               collectionName: nil)
                    items.append(fallback)
                }
            }
        } catch {
            // If load local fails, return empty array and log the error
            SimpleLogger.log("Failed to load local kworb: \(error)")
        }
        return items.sorted { $0.rank < $1.rank }
    }
}
