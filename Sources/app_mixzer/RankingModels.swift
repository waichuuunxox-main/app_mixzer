import Foundation

// Minimal model for local Kworb-like JSON
public struct KworbEntry: Codable, Sendable {
    public let rank: Int
    public let title: String
    public let artist: String
}

// Combined model for UI
public struct RankingItem: Identifiable, Sendable {
    public let id = UUID()
    public let rank: Int
    public let title: String
    public let artist: String
    public let artworkURL: URL?
    public let previewURL: URL?
    public let releaseDate: Date?
    public let collectionName: String?
}

// iTunes search API response models
public struct ITunesSearchResponse: Codable, Sendable {
    public let resultCount: Int
    public let results: [ITunesTrack]
}

public struct ITunesTrack: Codable, Sendable {
    public let trackName: String?
    public let artistName: String?
    public let artworkUrl100: String?
    public let previewUrl: String?
    public let releaseDate: String?
    public let collectionName: String?
}

extension ITunesTrack {
    func toRankingItem(from kworb: KworbEntry) -> RankingItem {
        let artwork = artworkUrl100.flatMap { URL(string: $0) }
        let preview = previewUrl.flatMap { URL(string: $0) }
        let date: Date?
        if let r = releaseDate {
            date = ISO8601DateFormatter().date(from: r)
        } else {
            date = nil
        }
        return RankingItem(rank: kworb.rank,
                           title: kworb.title,
                           artist: kworb.artist,
                           artworkURL: artwork,
                           previewURL: preview,
                           releaseDate: date,
                           collectionName: collectionName)
    }
}
