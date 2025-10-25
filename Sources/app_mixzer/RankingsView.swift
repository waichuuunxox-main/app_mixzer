import SwiftUI

@MainActor
final class RankingsViewModel: ObservableObject {
    @Published var items: [RankingItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    nonisolated private let service: RankingService

    init(service: RankingService = RankingService()) {
        self.service = service
    }

    func load() async {
            isLoading = true
            errorMessage = nil
            // Capture the service reference on the main actor, then run the network work off-main-thread
            let service = self.service
            let results = await Task.detached { await service.loadRanking() }.value
            await MainActor.run {
                if results.isEmpty {
                    errorMessage = "No ranking data available"
                }
                items = results
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
                        HStack(spacing: 12) {
                            RankView(rank: item.rank)
                            if let url = item.artworkURL {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .empty:
                                        Color.gray.opacity(0.2)
                                            .frame(width: 64, height: 64)
                                            .cornerRadius(6)
                                    case .success(let image):
                                        image.resizable()
                                            .scaledToFill()
                                            .frame(width: 64, height: 64)
                                            .cornerRadius(6)
                                    case .failure:
                                        Color.gray.opacity(0.2)
                                            .frame(width: 64, height: 64)
                                            .cornerRadius(6)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            } else {
                                Color.gray.opacity(0.2)
                                    .frame(width: 64, height: 64)
                                    .cornerRadius(6)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.headline)
                                Text(item.artist).font(.subheadline).foregroundColor(.secondary)
                                if let date = item.releaseDate {
                                    Text(Self.dateFormatter.string(from: date))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if let preview = item.previewURL {
                                Link("Preview", destination: preview)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Top 10 Charts")
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
