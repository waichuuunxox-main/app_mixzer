// 根據 MusicRankingLogic.md 的邏輯設計
// 模型說明: RankingItem 與 KworbEntry 等型別用於表示由 Kworb 提供之排行資料
// 與 iTunes API 回傳的曲目資料整合後的顯示模型。
// 請勿在此處存放 mock 資料；資料來源須為 Kworb（本地或遠端）與 iTunes Search API。
import Foundation

#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// Minimal model for local Kworb-like JSON
public struct KworbEntry: Codable, Sendable {
    public let rank: Int
    public let title: String
    public let artist: String
}

fileprivate extension String {
    /// Replace the first occurrence of a NxN token like "100x100" with the provided replacement.
    func firstMatchReplacingSize(with replacement: String) -> String? {
        // A simple scan for the first pattern of digitsxdigits using a regex search
        let pattern = "(\\d+)x(\\d+)"
        if let range = self.range(of: pattern, options: .regularExpression) {
            var s = self
            s.replaceSubrange(range, with: replacement)
            return s
        }
        return nil
    }
}

// Combined model for UI
public struct RankingItem: Identifiable, Sendable {
    /// Use the rank as a stable identifier so SwiftUI row identity remains constant
    /// across incremental updates (avoids reusing rows and artwork jumping).
    public var id: Int { rank }
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
        // iTunes often provides artwork URLs with size tokens like "100x100bb".
        // Replace common small sizes with a larger size (600x600) to improve resolution
        // when displaying artwork in modern UIs.
        let artwork: URL? = {
            guard let s = artworkUrl100 else { return nil }
            // Decide target size based on screen/backing scale when possible.
            // Default to 600. On Retina (2x) or HiDPI (3x) we request larger images to keep them crisp.
            var targetSize = 600

            #if canImport(AppKit)
            if let screen = NSScreen.main {
                let scale = Int(round(screen.backingScaleFactor))
                if scale >= 3 { targetSize = 1800 }
                else if scale == 2 { targetSize = 1200 }
            }
            #elseif canImport(UIKit)
            let scale = Int(round(UIScreen.main.scale))
            if scale >= 3 { targetSize = 1800 }
            else if scale == 2 { targetSize = 1200 }
            #endif

            // Replace common tokens (100x100, 200x200, etc.) with the chosen target size.
            // Use a simple regex-like approach for safety: replace the first occurrence of "\d+x\d+".
            if let replaced = s.firstMatchReplacingSize(with: "\(targetSize)x\(targetSize)") {
                return URL(string: replaced)
            }

            // Fallback: naive replace for "100x100" to be conservative.
            let higher = s.replacingOccurrences(of: "100x100", with: "\(targetSize)x\(targetSize)")
            return URL(string: higher)
        }()
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
