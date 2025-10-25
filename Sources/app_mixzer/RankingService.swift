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
        let cwd = FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: cwd).appendingPathComponent("docs/kworb_top10.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RankingError.fileNotFound
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode([KworbEntry].self, from: data)
        } catch {
            throw RankingError.parseError(error)
        }
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
            // If load local fails, return empty array
            print("Failed to load local kworb: \(error)")
        }
        return items.sorted { $0.rank < $1.rank }
    }
}
