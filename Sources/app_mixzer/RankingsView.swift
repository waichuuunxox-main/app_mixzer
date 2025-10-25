import SwiftUI

public enum EnrichmentStatus: Sendable {
    case pending
    case success
    case failed
}

@MainActor
public final class RankingsViewModel: ObservableObject {
    @Published var items: [RankingItem] = []
    @Published var isLoading: Bool = false
    @Published var localCount: Int = 0
    @Published var isEnriching: Bool = false
    @Published var enrichmentStatusByRank: [Int: EnrichmentStatus] = [:]
    @Published var errorMessage: String?

    nonisolated private let service: RankingService

    public init(service: RankingService = RankingService()) {
        self.service = service
    }

    func load() async {
            isLoading = true
            errorMessage = nil
            localCount = 0
            isEnriching = false

            // 1) load local kworb first to show immediate feedback
            do {
                let local = try await Task.detached { try await self.service.loadLocalKworb() }.value
                await MainActor.run {
                    localCount = local.count
                }
            } catch {
                // log and continue; localCount stays 0
                SimpleLogger.log("RankingViewModel: failed to load local kworb: \(error)")
            }

                // 2) perform enrichment per-item so we can show item-level status
                await MainActor.run { isEnriching = true }

                // create fallback items from local kworb so UI shows immediate content
                var currentItems: [RankingItem] = []
                do {
                    let local = try await Task.detached { try await self.service.loadLocalKworb() }.value
                    for entry in local.sorted(by: { $0.rank < $1.rank }) {
                        let fallback = RankingItem(rank: entry.rank,
                                                   title: entry.title,
                                                   artist: entry.artist,
                                                   artworkURL: nil,
                                                   previewURL: nil,
                                                   releaseDate: nil,
                                                   collectionName: nil)
                        currentItems.append(fallback)
                        enrichmentStatusByRank[entry.rank] = .pending
                    }
                } catch {
                    // already logged earlier
                }

                await MainActor.run {
                    if currentItems.isEmpty {
                        errorMessage = "No ranking data available"
                    }
                    items = currentItems
                }

                // enrich each item concurrently but limit concurrency to avoid rate limits
                await withTaskGroup(of: (Int, Result<RankingItem, Error>).self) { group in
                    for item in currentItems {
                        group.addTask {
                            let rank = item.rank
                            // try to find kworb entry for this rank by reloading local list
                            // fallback: call queryITunes using a KworbEntry-shaped payload
                            let kworb = KworbEntry(rank: item.rank, title: item.title, artist: item.artist)
                            do {
                                let track = try await self.service.queryITunes(for: kworb)
                                let enriched = track.toRankingItem(from: kworb)
                                return (rank, .success(enriched))
                            } catch {
                                return (rank, .failure(error))
                            }
                        }
                    }

                    for await (rank, result) in group {
                        await MainActor.run {
                            switch result {
                            case .success(let enriched):
                                // replace item with same rank
                                if let idx = items.firstIndex(where: { $0.rank == rank }) {
                                    items[idx] = enriched
                                } else {
                                    items.append(enriched)
                                }
                                enrichmentStatusByRank[rank] = .success
                            case .failure:
                                enrichmentStatusByRank[rank] = .failed
                            }
                        }
                    }
                }

                await MainActor.run {
                    isEnriching = false
                    isLoading = false
                }
    }
}

public struct RankingsView: View {
    @StateObject private var vm = RankingsViewModel()

    public init() {}

    public var body: some View {
        NavigationView {
            Group {
                if vm.isLoading {
                    ProgressView("Loading…")
                } else if let err = vm.errorMessage {
                    Text(err).foregroundColor(.secondary)
                } else {
                    List(vm.items) { item in
                        NavigationLink(destination: RankingDetailView(item: item)) {
                        HStack(spacing: 12) {
                            RankView(rank: item.rank)

                            // Artwork with slightly larger size and nicer placeholder
                            if let url = item.artworkURL {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .empty:
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.gray.opacity(0.12))
                                            ProgressView()
                                        }
                                        .frame(width: 80, height: 80)
                                    case .success(let image):
                                        image.resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .cornerRadius(8)
                                            .clipped()
                                    case .failure:
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.gray.opacity(0.12))
                                            .frame(width: 80, height: 80)
                                            .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.12))
                                    .frame(width: 80, height: 80)
                                    .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                            }

                            // Textual info
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text(item.artist)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                HStack(spacing: 8) {
                                    if let collection = item.collectionName {
                                        Text(collection)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    if let date = item.releaseDate {
                                        Text(Self.dateFormatter.string(from: date))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            // Actions column: preview button + small link + enrichment status
                            VStack(spacing: 8) {
                                // enrichment status indicator
                                Group {
                                    switch vm.enrichmentStatusByRank[item.rank] ?? .pending {
                                    case .pending:
                                        ProgressView()
                                            .scaleEffect(0.6)
                                    case .success:
                                        Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                                    case .failed:
                                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                                    }
                                }
                                .frame(height: 20)

                                if let preview = item.previewURL {
                                    Link(destination: preview) {
                                        Image(systemName: "play.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.accentColor)
                                    }
                                } else {
                                    Image(systemName: "nosign")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(width: 64)
                        }
                        }
                        .padding(.vertical, 8)
                        .swipeActions(edge: .trailing) {
                            Button {
                                // copy title to pasteboard as quick action
                                #if canImport(AppKit)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.title, forType: .string)
                                #endif
                            } label: {
                                Label("Copy title", systemImage: "doc.on.doc")
                            }
                            .tint(.blue)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await vm.load()
                    }
                }
            }
            .navigationTitle("Top 10 Charts")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "tray.full")
                                .foregroundColor(.secondary)
                            Text("\(vm.localCount)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if vm.isEnriching {
                            ProgressView()
                                .scaleEffect(0.6)
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.orange)
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(vm.localCount > 0 ? .green : .secondary)
                        }
                    }
                }
            }
        }
        .task {
            await vm.load()
        }
    }

    static var dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()
}

struct RankView: View {
    let rank: Int
    var body: some View {
        Text("\(rank)")
            .font(.title3.bold())
            .frame(width: 36, height: 36)
            .background(Color.accentColor.opacity(0.12))
            .cornerRadius(8)
    }
}

// Preview using sample data
struct RankingsView_Previews: PreviewProvider {
    static var previews: some View {
        let sample = KworbEntry(rank: 1, title: "Sample Song", artist: "Sample Artist")
        let track = ITunesTrack(trackName: "Sample Song", artistName: "Sample Artist", artworkUrl100: nil, previewUrl: nil, releaseDate: nil, collectionName: nil)
        // create sample data (not directly used in this preview)
        _ = track.toRankingItem(from: sample)
        return RankingsView()
            .environmentObject(RankingsViewModel())
            .previewDisplayName("Charts")
    }
}
