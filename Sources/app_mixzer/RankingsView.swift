// 根據 MusicRankingLogic.md 的邏輯設計
// UI 負責將整合後的排行榜資料呈現為 List / master-detail
// 資料來源: Kworb (本地 kworb_top10.json) -> iTunes Search API (曲目細節)
// 規則：不播放音樂；只提供預覽連結與跳轉。匯出功能遵循 CSV 格式（rank,title,artist,collection,releaseDate,previewURL,artworkURL）。
import SwiftUI
import Network
import AppKit

fileprivate let rankingsDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    return f
}()

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
        @Published public var sourceDescription: String = "local"
        @Published public var lastUpdated: Date?
    @Published public var fetchMessage: String? = nil
    @Published public var fetchWasSuccess: Bool = false
        @Published public var totalToEnrich: Int = 0
        @Published public var enrichedCount: Int = 0
        // Session token to avoid race where an earlier/slow load overwrites a later one
        private var currentLoadID: UUID? = nil
        // Injected service (useful for tests); default to concrete implementation
        private let service: RankingServiceProtocol

    public init(service: RankingServiceProtocol = RankingService()) {
        // initialize stored properties before calling methods that capture `self`
        self.service = service

        // Observe enrichment notifications and update on main actor
        NotificationCenter.default.addObserver(self, selector: #selector(didEnrichItem(_:)), name: .appMixzerDidEnrichItem, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRequestRefresh(_:)), name: .appMixzerRequestRefresh, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(userDefaultsDidChange(_:)), name: UserDefaults.didChangeNotification, object: nil)
        startNetworkMonitor()
        
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func didEnrichItem(_ note: Notification) {
        guard let item = note.object as? RankingItem else { return }
        if let idx = items.firstIndex(where: { $0.rank == item.rank }) {
            items[idx] = item
            // Decide success/failure based on whether we have useful enriched fields
            let success = (item.artworkURL != nil) || (item.previewURL != nil)
            enrichmentStatusByRank[item.rank] = success ? .success : .failed
            if success { enrichedCount += 1 }
        }
    }

    @objc private func handleRequestRefresh(_ note: Notification) {
        SimpleLogger.log("DEBUG: RankingsViewModel.handleRequestRefresh -> notification received: \(note.name.rawValue)")
        Task { await load() }
    }

    @objc private func userDefaultsDidChange(_ note: Notification) {
        // Start/stop auto-update based on toggled user setting
        let enabled = UserDefaults.standard.bool(forKey: "autoUpdateEnabled")
        Task { if enabled { await startAutoUpdateIfNeeded() } else { stopAutoUpdate() } }
    }

    private var autoUpdateTask: Task<Void, Never>? = nil
    private var pathMonitor: NWPathMonitor? = nil
    private var currentPath: NWPath? = nil
    // Signal source for external refresh triggers (SIGUSR1)
    

    private func startNetworkMonitor() {
        pathMonitor = NWPathMonitor()
        let q = DispatchQueue(label: "app_mixzer.nwmonitor")
        pathMonitor?.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.currentPath = path
            }
        }
        pathMonitor?.start(queue: q)
    }

    private func stopNetworkMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    private func isNetworkSuitable() -> Bool {
        guard let path = currentPath else { return true }
        if path.status != .satisfied { return false }
        let onlyWifi = UserDefaults.standard.bool(forKey: "autoUpdateOnlyOnWiFi")
        if onlyWifi {
            return path.usesInterfaceType(.wifi)
        }
        // Otherwise accept any satisfied path (optionally could refuse expensive)
        let allowExpensive = true
        if !allowExpensive && path.isExpensive { return false }
        return true
    }

    private func stopAutoUpdate() {
        autoUpdateTask?.cancel()
        autoUpdateTask = nil
    }
    

    private func startAutoUpdateIfNeeded() async {
        guard autoUpdateTask == nil else { return }
        let enabled = UserDefaults.standard.bool(forKey: "autoUpdateEnabled")
        guard enabled else { return }
        let interval = UserDefaults.standard.integer(forKey: "autoUpdateIntervalSeconds")
        let seconds = interval > 0 ? interval : 3600

        autoUpdateTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Sleep for interval
                do {
                    try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                } catch {
                    break
                }

                if Task.isCancelled { break }

                // Respect latest setting
                if !UserDefaults.standard.bool(forKey: "autoUpdateEnabled") { break }

                await MainActor.run {
                    self.isEnriching = true
                }

                let svc = RankingService()
                let remoteURLString = UserDefaults.standard.string(forKey: "remoteKworbURL") ?? ""
                let remoteURL = URL(string: remoteURLString)
                let result = await svc.loadRanking(remoteURL: remoteURL, maxConcurrency: 6, topN: nil)

                await MainActor.run {
                    if result.isEmpty {
                        self.fetchWasSuccess = false
                        self.fetchMessage = "Auto-update failed"
                    } else {
                        self.items = result
                        self.localCount = result.count
                        for item in result { self.enrichmentStatusByRank[item.rank] = .success }
                        self.lastUpdated = Date()
                        self.fetchWasSuccess = true
                        self.fetchMessage = "Auto-update succeeded"
                    }
                    self.isEnriching = false
                }
            }
        }
    }

    public func load() async {
        isEnriching = true
        // record a unique token for this load; other concurrent loads will be ignored when they finish
        let myLoadID = UUID()
        currentLoadID = myLoadID
        // Log important UserDefaults that affect source selection so we can debug which branch is used at runtime
        let remoteURLString = UserDefaults.standard.string(forKey: "remoteKworbURL") ?? ""
        let useApple = UserDefaults.standard.bool(forKey: "useAppleRSS")
        let appleCountry = UserDefaults.standard.string(forKey: "appleRSSCountry") ?? "us"
        let appleLimit = UserDefaults.standard.integer(forKey: "appleRSSLimit")
        SimpleLogger.log("DEBUG: RankingsViewModel.load -> remoteKworbURL='\(remoteURLString)', useAppleRSS=\(useApple), appleRSSCountry=\(appleCountry), appleRSSLimit=\(appleLimit)")
        defer { isEnriching = false }

        // Determine remote URL setting (if present)
        var remoteURL: URL? = nil
        if let s = UserDefaults.standard.string(forKey: "remoteKworbURL"), !s.trimmingCharacters(in: .whitespaces).isEmpty {
            remoteURL = URL(string: s)
            sourceDescription = "remote"
        } else {
            sourceDescription = "local"
        }

        // Try to load immediate entries for fast UI render: prefer remote list if available, else optionally use Apple RSS, fallback to local
    var entries: [KworbEntry] = []
    let svc = self.service
        do {
            if let r = remoteURL, !r.absoluteString.trimmingCharacters(in: .whitespaces).isEmpty {
                entries = try await svc.loadRemoteKworb(from: r, timeout: 12, maxBytes: 2_000_000)
                sourceDescription = "remote"
            } else if UserDefaults.standard.bool(forKey: "useAppleRSS") {
                // Read configured country/limit
                let country = UserDefaults.standard.string(forKey: "appleRSSCountry") ?? "us"
                let limit = UserDefaults.standard.integer(forKey: "appleRSSLimit")
                let safeLimit = limit > 0 ? limit : 100
                entries = try await svc.loadAppleRSSTopSongs(country: country, limit: safeLimit)
                sourceDescription = "apple rss"
            } else {
                entries = try await svc.loadLocalKworb()
                sourceDescription = "local"
            }
        } catch {
            SimpleLogger.log("Failed to load initial kworb list: \(error) — falling back to local")
            do {
                entries = try await svc.loadLocalKworb()
                sourceDescription = "local"
            } catch {
                entries = []
            }
        }

        // Populate minimal items so the UI can render quickly
        let minimal = entries.map { e in
            RankingItem(rank: e.rank, title: e.title, artist: e.artist, artworkURL: nil, previewURL: nil, releaseDate: nil, collectionName: nil)
        }
        // Only apply the initial minimal set if this load is still the latest
        guard currentLoadID == myLoadID else {
            SimpleLogger.log("DEBUG: RankingsViewModel.load -> aborting initial update because a newer load started (loadID=\(myLoadID.uuidString))")
            return
        }
        SimpleLogger.log("DEBUG: RankingsViewModel.load -> applying initial minimal items count=\(minimal.count) (loadID=\(myLoadID.uuidString))")
        self.items = minimal.sorted { $0.rank < $1.rank }
        self.localCount = self.items.count
        // mark all incoming entries as pending enrichment so the UI shows progress state
        for e in entries { self.enrichmentStatusByRank[e.rank] = .pending }
        // Prepare progress counters
        self.totalToEnrich = entries.count
        self.enrichedCount = 0

        // Incremental updates are handled by the main-actor selector observer installed in init().

        // Kick off the controlled concurrent enrichment in background
        Task.detached { @MainActor in
            self.isEnriching = true
        }
        let final: [RankingItem]
        if remoteURL == nil && UserDefaults.standard.bool(forKey: "useAppleRSS") {
            // We already fetched Apple RSS entries above into `entries` — ask the service
            // to enrich those specific entries instead of re-reading local kworb.
            final = await svc.loadRanking(remoteURL: nil, maxConcurrency: 6, topN: nil, initialEntries: entries)
        } else {
            final = await svc.loadRanking(remoteURL: remoteURL, maxConcurrency: 6, topN: nil, initialEntries: nil)
        }
        // Final update: only apply if this load is still the latest
        DispatchQueue.main.async {
            guard self.currentLoadID == myLoadID else {
                SimpleLogger.log("DEBUG: RankingsViewModel.load -> discarding final results from an outdated load session (loadID=\(myLoadID.uuidString))")
                return
            }
            SimpleLogger.log("DEBUG: RankingsViewModel.load -> applying final results count=\(final.count) (loadID=\(myLoadID.uuidString))")
            self.items = final
            self.localCount = final.count
            for item in final {
                let success = (item.artworkURL != nil) || (item.previewURL != nil)
                self.enrichmentStatusByRank[item.rank] = success ? .success : .failed
            }
            self.lastUpdated = Date()
            self.isEnriching = false
        }
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
    @State private var showingFetchAlert: Bool = false
    @Namespace private var artworkNamespace
    @State private var searchText: String = ""
    @AppStorage("compactSidebar") private var compactSidebar: Bool = false

    public init() {}

    public var body: some View {
        NavigationSplitView {
            // Left: main dashboard / detail area (primary)
            if let rank = selectedRank, let item = vm.items.first(where: { $0.rank == rank }) {
                RankingDetailView(item: item, namespace: artworkNamespace, isSelected: selectedRank == item.rank)
            } else {
                // Simple dashboard summary when nothing selected
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "chart.bar.fill")
                            .font(.largeTitle)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading) {
                            Text("Top 10 Charts").font(.title2).bold()
                            HStack(spacing: 8) {
                                Text("Entries: \(vm.localCount)").font(.subheadline).foregroundColor(.secondary)
                                Text("•") .foregroundColor(.secondary)
                                Text(vm.sourceDescription.capitalized).font(.subheadline).foregroundColor(.secondary)
                                if let d = vm.lastUpdated {
                                    Text("•") .foregroundColor(.secondary)
                                    Text("Last: \(rankingsDateFormatter.string(from: d))").font(.subheadline).foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    HStack(spacing: 18) {
                        VStack(alignment: .leading) {
                            Text("Enrichment").font(.caption).foregroundColor(.secondary)
                            if vm.isEnriching {
                                ProgressView(value: Double(vm.enrichedCount), total: Double(max(1, vm.totalToEnrich)))
                                    .scaleEffect(0.9)
                            }
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
                    ForEach(filteredItems(vm.items, search: searchText), id: \.rank) { item in
                            RankingRow(item: item,
                                       enrichment: vm.enrichmentStatusByRank[item.rank] ?? .pending,
                                       namespace: artworkNamespace,
                                       isSelected: Binding(get: { selectedRank == item.rank }, set: { new in selectedRank = new ? item.rank : nil }),
                                       compact: compactSidebar)
                            .tag(item.rank)
                            .onAppear {
                                // Prefetch next 3 items' artwork at a modest size to improve scroll experience
                                Task.detached { [items = vm.items] in
                                    guard let idx = items.firstIndex(where: { $0.rank == item.rank }) else { return }
                                    let prefetchCount = 3
                                    for offset in 1...prefetchCount {
                                        let nextIdx = idx + offset
                                        if nextIdx < items.count, let url = items[nextIdx].artworkURL {
                                            // use a small pixel size for prefetch (thumbnail)
                                            _ = await ImageCache.shared.image(for: url, maxPixelSize: 200)
                                        }
                                    }
                                }
                            }
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
        .onChange(of: selectedRank) { _old, newValue in
            SimpleLogger.log("DEBUG: RankingsView.selection changed -> \(String(describing: newValue))")
        }
        .overlay(
            Group {
                if let msg = vm.fetchMessage {
                    HStack {
                        Image(systemName: vm.fetchWasSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundColor(vm.fetchWasSuccess ? .green : .red)
                        Text(msg).foregroundColor(.primary)
                        Spacer()
                        Button(action: { vm.fetchMessage = nil }) { Text("Dismiss") }
                    }
                    .padding(10)
                    .background(VisualEffectView(material: .popover, blendingMode: .withinWindow))
                    .cornerRadius(10)
                    .padding()
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            , alignment: .top
        )
    }

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
                        .matchedGeometryEffect(id: "artwork-\(item.rank)", in: namespace, properties: .frame, anchor: .center, isSource: !isSelected)
                            .accessibilityLabel(Text("Artwork for \(item.title) by \(item.artist)"))
                    }
                }
                // avoid using the artwork URL as the view identity; row identity is controlled by the ForEach's item id (rank)
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
                            Text(rankingsDateFormatter.string(from: date)).font(.caption).foregroundColor(.secondary)
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
        .onAppear {
            SimpleLogger.log("DEBUG: RankingRow.onAppear rank=\(item.rank) isSelected=\(isSelected)")
        }
        .onChange(of: isSelected) { _old, newValue in
            SimpleLogger.log("DEBUG: RankingRow.onChange isSelected=\(newValue) rank=\(item.rank)")
        }
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

// Small NSVisualEffect wrapper for nice banner background (macOS)

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
