import SwiftUI

public enum EnrichmentStatus: Sendable {
    case pending
    case success
    case failed
}

@MainActor
public final class RankingsViewModel: ObservableObject {
    @Published public var items: [RankingItem] = []
    @Published public var localCount: Int = 0
    @Published public var isEnriching: Bool = false
    @Published public var enrichmentStatusByRank: [Int: EnrichmentStatus] = [:]

    public init() {}

    public func load() async {
        isEnriching = true
        defer { isEnriching = false }

        // Use the existing high-level loader which already queries iTunes where possible.
        let loaded = await RankingService().loadRanking()
        self.items = loaded
        self.localCount = loaded.count

        // Mark items as enriched; the loadRanking already attempted enrichment per item.
        for item in loaded { enrichmentStatusByRank[item.rank] = .success }
    }

    /// Export current items as CSV into a temporary file and return the URL.
    /// Columns: rank,title,artist,collection,releaseDate,previewURL,artworkURL
    public func exportCSV() async -> URL? {
        guard !items.isEmpty else { return nil }
        var lines: [String] = []
        lines.append("rank,title,artist,collection,releaseDate,previewURL,artworkURL")
        for it in items {
            let title = it.title.replacingOccurrences(of: "\"", with: "\"")
            let artist = it.artist.replacingOccurrences(of: "\"", with: "\"")
            let collection = it.collectionName?.replacingOccurrences(of: "\"", with: "\"") ?? ""
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            let date = it.releaseDate.map { dateFormatter.string(from: $0) } ?? ""
            let preview = it.previewURL?.absoluteString ?? ""
            let artwork = it.artworkURL?.absoluteString ?? ""
            let row = "\(it.rank),\"\(title)\",\"\(artist)\",\"\(collection)\",\"\(date)\",\"\(preview)\",\"\(artwork)\""
            lines.append(row)
        }

        let csv = lines.joined(separator: "\n")
        let tmp = FileManager.default.temporaryDirectory
        let filename = "rankings_export_\(Int(Date().timeIntervalSince1970)).csv"
        let url = tmp.appendingPathComponent(filename)
        do {
            try csv.data(using: .utf8)?.write(to: url)
            SimpleLogger.log("Exported CSV to: \(url.path)")
            return url
        } catch {
            SimpleLogger.log("Failed to export CSV: \(error)")
            return nil
        }
    }
}

public struct RankingsView: View {
    @StateObject private var vm = RankingsViewModel()
    @State private var selectedRank: Int?
    @State private var showingSettings: Bool = false
    @State private var showingExportAlert: Bool = false
    @State private var exportedPath: String = ""

    public init() {}

    public var body: some View {
        NavigationSplitView {
            // Sidebar list
            List(selection: $selectedRank) {
                ForEach(vm.items) { item in
                    HStack(spacing: 12) {
                        RankView(rank: item.rank)

                        // Artwork (small)
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

                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(.headline).lineLimit(2)
                            Text(item.artist).font(.subheadline).foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                if let collection = item.collectionName {
                                    Text(collection).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                }
                                if let date = item.releaseDate {
                                    Text(Self.dateFormatter.string(from: date)).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }

                        Spacer()

                        VStack(spacing: 8) {
                            switch vm.enrichmentStatusByRank[item.rank] ?? .pending {
                            case .pending:
                                ProgressView().scaleEffect(0.6)
                            case .success:
                                Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                            case .failed:
                                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                            }

                            if let preview = item.previewURL {
                                Link(destination: preview) {
                                    Image(systemName: "play.circle.fill").font(.title2).foregroundColor(.accentColor)
                                }
                            } else {
                                Image(systemName: "nosign").foregroundColor(.secondary)
                            }
                        }
                        .frame(width: 64)
                    }
                    .padding(.vertical, 8)
                    .swipeActions(edge: .trailing) {
                        Button {
                            #if canImport(AppKit)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.title, forType: .string)
                            #endif
                        } label: {
                            Label("Copy title", systemImage: "doc.on.doc")
                        }
                        .tint(.blue)
                    }
                    .tag(item.rank)
                }
            }
            .listStyle(.plain)
            .refreshable { await vm.load() }
        } detail: {
            if let rank = selectedRank, let item = vm.items.first(where: { $0.rank == rank }) {
                RankingDetailView(item: item)
            } else {
                VStack(alignment: .center, spacing: 12) {
                    Text("No item selected").font(.title2).foregroundColor(.secondary)
                    Text("Select a chart row on the left to see details, play preview, or view metadata.")
                        .multilineTextAlignment(.center).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Top 10 Charts")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.full").foregroundColor(.secondary)
                        Text("\(vm.localCount)").font(.subheadline).foregroundColor(.secondary)
                    }
                    if vm.isEnriching {
                        ProgressView().scaleEffect(0.6)
                        Image(systemName: "bolt.fill").foregroundColor(.orange)
                    } else {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(vm.localCount > 0 ? .green : .secondary)
                    }
                }
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { Task { await vm.load() } }) { Label("Refresh", systemImage: "arrow.clockwise") }
            }
            ToolbarItem(placement: .automatic) {
                HStack {
                    Button {
                        Task {
                            if let url = await vm.exportCSV() {
                                exportedPath = url.path
                                showingExportAlert = true
                            } else {
                                exportedPath = ""
                                showingExportAlert = true
                            }
                        }
                    } label: { Image(systemName: "square.and.arrow.up") }

                    Button {
                        showingSettings.toggle()
                    } label: { Image(systemName: "gearshape") }
                    .sheet(isPresented: $showingSettings) {
                        SettingsView()
                    }
                }
            }
        }
        .task { await vm.load() }
    }

    static let dateFormatter: DateFormatter = {
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
        _ = track.toRankingItem(from: sample)
        return RankingsView()
            .environmentObject(RankingsViewModel())
            .previewDisplayName("Charts")
    }
}
