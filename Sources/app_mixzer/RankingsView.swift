// 根據 MusicRankingLogic.md 的邏輯設計
// UI 負責將整合後的排行榜資料呈現為 List / master-detail
// 資料來源: Kworb (本地 kworb_top10.json) -> iTunes Search API (曲目細節)
// 規則：不播放音樂；只提供預覽連結與跳轉。匯出功能遵循 CSV 格式（rank,title,artist,collection,releaseDate,previewURL,artworkURL）。
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
    @Namespace private var artworkNamespace
    @State private var searchText: String = ""
    @AppStorage("compactSidebar") private var compactSidebar: Bool = false

    public init() {}

    public var body: some View {
        NavigationSplitView {
            // Left: main dashboard / detail area (primary)
            if let rank = selectedRank, let item = vm.items.first(where: { $0.rank == rank }) {
                RankingDetailView(item: item, namespace: artworkNamespace)
            } else {
                // Simple dashboard summary when nothing selected
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "chart.bar.fill")
                            .font(.largeTitle)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading) {
                            Text("Top 10 Charts").font(.title2).bold()
                            Text("Local entries: \(vm.localCount)").font(.subheadline).foregroundColor(.secondary)
                        }
                    }

                    HStack(spacing: 18) {
                        VStack(alignment: .leading) {
                            Text("Enrichment").font(.caption).foregroundColor(.secondary)
                            if vm.isEnriching { ProgressView().scaleEffect(0.9) }
                        }

                        VStack(alignment: .leading) {
                            Text("Cache stats").font(.caption).foregroundColor(.secondary)
                            Text("")
                        }
                    }

                    Divider()

                    Text("Select a chart row on the right to see details, play preview, or view metadata.")
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } detail: {
            // Right: item list shown as a sidebar (narrow)
            VStack(spacing: 6) {
                SidebarSearchField(text: $searchText, placeholder: "Search title, artist, album")
                    .frame(height: 28)
                    .padding(.horizontal, 8)

                List(selection: $selectedRank) {
                    ForEach(filteredItems(vm.items, search: searchText)) { item in
                        RankingRow(item: item,
                                   enrichment: vm.enrichmentStatusByRank[item.rank] ?? .pending,
                                   namespace: artworkNamespace,
                                   isSelected: Binding(get: { selectedRank == item.rank }, set: { new in selectedRank = new ? item.rank : nil }),
                                   compact: compactSidebar)
                        .tag(item.rank)
                    }
                }
                .listStyle(.sidebar)
                .frame(minWidth: compactSidebar ? 220 : 260)
                .refreshable { await vm.load() }
            }
        }
        .navigationTitle("Top 10 Charts")
        // animate detail pane transitions when selection changes
        .animation(.easeInOut(duration: 0.22), value: selectedRank)
        .alert(isPresented: $showingExportAlert) {
            if exportedPath.isEmpty {
                return Alert(title: Text("Export Failed"), message: Text("CSV export failed."), dismissButton: .default(Text("OK")))
            } else {
                return Alert(title: Text("Exported CSV"), message: Text("Saved to: \(exportedPath)"), primaryButton: .default(Text("Reveal"), action: {
                    #if canImport(AppKit)
                    NSWorkspace.shared.selectFile(exportedPath, inFileViewerRootedAtPath: "")
                    #endif
                }), secondaryButton: .cancel())
            }
        }
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
                                // Post a system notification for export success
                                Task { await NotificationHelper.shared.postExportNotification(fileURL: url) }
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
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation { compactSidebar.toggle() }
                } label: {
                    Image(systemName: compactSidebar ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                }
                .help("Toggle compact sidebar")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    NotificationCenter.default.post(name: .appMixzerFocusSidebarSearch, object: nil)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Focus sidebar search (⌘F)")
                .keyboardShortcut("f", modifiers: .command)
            }
        }
        .onAppear {
            // Try to auto-focus the sidebar search after the view/window is ready.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                NotificationCenter.default.post(name: .appMixzerFocusSidebarSearch, object: nil)
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

// Helper: filter items by search text (title, artist, collection)
fileprivate func filteredItems(_ items: [RankingItem], search: String) -> [RankingItem] {
    let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !q.isEmpty else { return items }
    return items.filter { item in
        if item.title.lowercased().contains(q) { return true }
        if item.artist.lowercased().contains(q) { return true }
        if let c = item.collectionName?.lowercased(), c.contains(q) { return true }
        return false
    }
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

// Separate row view to manage hover state and quick actions
struct RankingRow: View {
    let item: RankingItem
    let enrichment: EnrichmentStatus
    let namespace: Namespace.ID
    @Binding var isSelected: Bool
    let compact: Bool

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            RankView(rank: item.rank)

            let artworkSize: CGFloat = compact ? 48 : 80

            if let url = item.artworkURL {
                Group {
                    CachedAsyncImage(url: url) {
                        ZStack {
                            RoundedRectangle(cornerRadius: compact ? 6 : 8)
                                .fill(Color.gray.opacity(0.12))
                            if !compact { ProgressView() }
                        }
                        .frame(width: artworkSize, height: artworkSize)
                            } content: { img in
                                img
                                    .renderingMode(.original)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: artworkSize, height: artworkSize)
                            .cornerRadius(compact ? 6 : 8)
                            .clipped()
                            .matchedGeometryEffect(id: "artwork-\(item.rank)", in: namespace)
                            .accessibilityLabel(Text("Artwork for \(item.title) by \(item.artist)"))
                    }
                }
                .id(url.absoluteString)
            } else {
                RoundedRectangle(cornerRadius: compact ? 6 : 8)
                    .fill(Color.gray.opacity(0.12))
                    .frame(width: artworkSize, height: artworkSize)
                    .overlay(Image(systemName: "photo").foregroundColor(.secondary))
            }

            VStack(alignment: .leading, spacing: compact ? 2 : 6) {
                Text(item.title)
                    .font(compact ? .subheadline.bold() : .headline)
                    .lineLimit(compact ? 1 : 2)
                Text(item.artist)
                    .font(compact ? .caption : .subheadline)
                    .foregroundColor(.secondary)

                if !compact {
                    HStack(spacing: 8) {
                        if let collection = item.collectionName {
                            Text(collection).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                        if let date = item.releaseDate {
                            Text(RankingsView.dateFormatter.string(from: date)).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }

            Spacer()

            // enrichment + preview icon remain visible; shrink when compact
            VStack(spacing: compact ? 6 : 8) {
                switch enrichment {
                case .pending:
                    ProgressView().scaleEffect(compact ? 0.5 : 0.6)
                case .success:
                    Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                }

                if let preview = item.previewURL {
                    Link(destination: preview) {
                        Image(systemName: "play.circle.fill").font(compact ? .body : .title2).foregroundColor(.accentColor)
                    }
                } else {
                    Image(systemName: "nosign").foregroundColor(.secondary)
                }
            }
            .frame(width: compact ? 46 : 64)

            if hovering && !compact {
                HStack(spacing: 8) {
                    Button {
                        #if canImport(AppKit)
                        let paste = NSPasteboard.general
                        paste.clearContents()
                        paste.setString(item.title, forType: .string)
                        #endif
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)

                    if let preview = item.previewURL {
                        Button {
                            #if canImport(AppKit)
                            NSWorkspace.shared.open(preview)
                            #endif
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.vertical, compact ? 6 : 8)
        .contentShape(Rectangle())
        .onHover { over in
            withAnimation(.easeInOut(duration: 0.15)) { hovering = over }
        }
        .onTapGesture { isSelected = true }
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
