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
        /*
         Layout Contract (SINGLE SOURCE OF TRUTH)
         ------------------------------------------------------------
         IMPORTANT: This repository and runtime rely on this exact layout
         being preserved. Any future change that modifies the structure or
         sizing semantics below must be reviewed and approved.

         - Top-level container: GeometryReader { geo in HStack(spacing: 0) { ... } }
         - LEFT pane  : `rightPaneView()` — fixed width = geo.size.width * 0.35
         - Divider    : standard `Divider()` between panes
         - RIGHT pane : `sidebarView()` — fixed width = geo.size.width * 0.65
         - The HStack uses spacing == 0 and the entire HStack is constrained to
             `.frame(maxWidth: .infinity, maxHeight: .infinity)`.
         - Each `RankingRow` reserves a trailing transparent view of
             `reservedWidth = hoverWidth + trailingStatusWidth` so the overlay
             controls do NOT participate in the HStack layout; this prevents the
             song-info from drifting.

         Verification & automation:
         - A repo-level script `scripts/check_layout_contract.sh` checks the
             presence of the literal multipliers (0.35/0.65) in this file as a
             guard against accidental edits. Run it locally or include it in CI.
         - At runtime we emit an INFO log entry on appear indicating the
             declared fractions; tools/ops can assert this is present in the app
             log when launched from Finder/Dock.
        */
    @StateObject private var vm = RankingsViewModel()
    @State private var selectedRank: Int?
    @State private var showingSettings: Bool = false
    @State private var showingExportAlert: Bool = false
    @State private var exportedPath: String = ""
    @State private var showingFetchAlert: Bool = false
    @Namespace private var artworkNamespace
    @State private var searchText: String = ""
    @AppStorage("compactSidebar") private var compactSidebar: Bool = false
    // Embedded preview player state: when set, dashboard will show an inline player
    @State private var embeddedPreviewURL: URL? = nil
    @State private var embeddedPlayerAutoplay: Bool = true

    public init() {}

    // Split the body into a simpler, compiler-friendly structure to avoid
    // deep nested expressions that can trigger type-check/timeouts.
    public var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // 左側面板：佔整體寬度的 35%
                rightPaneView()
                    .frame(width: max(0, geo.size.width * 0.35))

                Divider()

                // 右側面板：佔整體寬度的 65%
                sidebarView()
                    .frame(width: max(0, geo.size.width * 0.65))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .toolbar { toolbarContent() }
        .onAppear {
            // Emit a stable INFO log that records the declared layout contract
            // so that launched app bundles can be verified against this contract.
            SimpleLogger.log("INFO: RankingsView.layoutContract -> leftFraction=0.35 rightFraction=0.65 reservedTrailing=hoverWidth+trailingStatusWidth")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                NotificationCenter.default.post(name: .appMixzerFocusSidebarSearch, object: nil)
            }
        }
        .task { await vm.load() }
        .onChange(of: selectedRank) { _old, newValue in
            SimpleLogger.log("DEBUG: RankingsView.selection changed -> \(String(describing: newValue))")
        }
        .overlay(topMessageOverlay(), alignment: .top)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func sidebarView() -> some View {
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
                               compact: compactSidebar,
                               onRequestPreview: { url in
                        // Show embedded player in dashboard area
                        embeddedPreviewURL = url
                        embeddedPlayerAutoplay = true
                    })
                        .tag(item.rank)
                }
            }
            .listStyle(.sidebar)
            .refreshable { await vm.load() }
        }
    }

    @ViewBuilder
    private func rightPaneView() -> some View {
        Group {
            if let rank = selectedRank, let item = vm.items.first(where: { $0.rank == rank }) {
                RankingDetailView(item: item, namespace: artworkNamespace, isSelected: selectedRank == item.rank)
            } else {
                // Dashboard
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "chart.bar.fill")
                            .font(.largeTitle)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading) {
                            Text("Top 10 Charts").font(.title2).bold()
                            HStack(spacing: 8) {
                                Text("Entries: \(vm.localCount)").font(.subheadline).foregroundColor(.secondary)
                                Text("•").foregroundColor(.secondary)
                                Text(vm.sourceDescription.capitalized).font(.subheadline).foregroundColor(.secondary)
                                if let d = vm.lastUpdated {
                                    Text("•").foregroundColor(.secondary)
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

                    Text("Select a chart row on the left to see details, play preview, or view metadata.")
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // Embedded preview player shown directly under the dashboard area when requested
                if let url = embeddedPreviewURL {
                    EmbeddedPlayerView(url: url, isPresented: Binding(get: { embeddedPreviewURL != nil }, set: { newVal in if !newVal { embeddedPreviewURL = nil } }))
                        .padding([.leading, .trailing, .bottom])
                }
            }
        }
    }

    // MARK: - Toolbar & Overlays

    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
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
                .sheet(isPresented: $showingSettings) { SettingsView() }
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

    @ViewBuilder
    private func topMessageOverlay() -> some View {
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
    // Callback to request an embedded preview to play in the dashboard area
    let onRequestPreview: ((URL) -> Void)?

    @State private var hovering = false
    // Diagnostics: capture geometry to確認文字區塊是否緊貼 artwork
    @State private var diag_artworkMaxX: CGFloat? = nil
    @State private var diag_textMinX: CGFloat? = nil
    @State private var diag_loggedInitial: Bool = false
    // 比照使用者 INFO 診斷：主內容右邊界與尾端 overlay 左邊界
    @State private var diag_mainMaxX: CGFloat? = nil
    @State private var diag_trailingMinX: CGFloat? = nil

    var body: some View {
        let hoverWidth: CGFloat = compact ? 60 : 80
        let trailingStatusWidth: CGFloat = compact ? 56 : 72
        let reservedWidth: CGFloat = hoverWidth + trailingStatusWidth

        HStack(spacing: 12) {
            // 左側群組：名次 + 專輯圖，固定寬度，確保右側文字不會侵入
            let artworkSize: CGFloat = compact ? 48 : 80
            let leftClusterWidth: CGFloat = 36 + 12 + artworkSize // RankView(36) + spacing(12) + artwork
            HStack(spacing: 12) {
                RankView(rank: item.rank)

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
                    // 記錄 artwork 的右邊界（在列座標系）
                    .background(GeometryReader { proxy in
                        Color.clear.onAppear {
                            let right = proxy.frame(in: .named("RankingRowCS-\(item.rank)")) .maxX
                            diag_artworkMaxX = right
                        }
                        .onChange(of: proxy.size) { _old, _ in
                            let right = proxy.frame(in: .named("RankingRowCS-\(item.rank)")) .maxX
                            diag_artworkMaxX = right
                        }
                    })
                    // avoid using the artwork URL as the view identity; row identity is controlled by the ForEach's item id (rank)
                } else {
                    RoundedRectangle(cornerRadius: compact ? 6 : 8)
                        .fill(Color.gray.opacity(0.12))
                        .frame(width: artworkSize, height: artworkSize)
                        .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                }
            }
            .frame(width: leftClusterWidth, alignment: .leading)

            // 右側：文字資訊
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
            // 主文字區塊填滿可用空間並固定靠左，確保緊貼 artwork
            .frame(maxWidth: .infinity, alignment: .leading)
            // 提高優先權避免尾端保留區造成壓縮
            .layoutPriority(1)
            // 記錄文字區塊的左邊界與右邊界（在列座標系）
            .background(GeometryReader { proxy in
                Color.clear.onAppear {
                    let frame = proxy.frame(in: .named("RankingRowCS-\(item.rank)"))
                    diag_textMinX = frame.minX
                    diag_mainMaxX = frame.maxX
                }
                .onChange(of: proxy.size) { _old, _ in
                    let frame = proxy.frame(in: .named("RankingRowCS-\(item.rank)"))
                    diag_textMinX = frame.minX
                    diag_mainMaxX = frame.maxX
                }
            })

            // 以實體透明視圖保留尾端寬度，穩定參與 HStack 佈局，避免 padding 在初期度量造成抖動
            Color.clear
                .frame(width: reservedWidth, height: 1)
        }
        .padding(.vertical, compact ? 6 : 8)
        .contentShape(Rectangle())
        // 注意：不使用 trailing padding 預留空間，改由上方透明視圖固定寬度
        // 提供列級的命名座標系供診斷用
        .coordinateSpace(name: "RankingRowCS-\(item.rank)")
        // 當兩側座標就緒時記錄 Δ
        .onChange(of: diag_textMinX) { _old, _ in
            logDiagIfReady()
        }
        .onChange(of: diag_artworkMaxX) { _old, _ in
            logDiagIfReady()
        }
        .onChange(of: diag_mainMaxX) { _old, _ in
            logDiagIfReady()
        }
        .onChange(of: diag_trailingMinX) { _old, _ in
            logDiagIfReady()
        }
        .onAppear {
            SimpleLogger.log("DEBUG: RankingRow.onAppear rank=\(item.rank) isSelected=\(isSelected)")
            logDiagIfReady()
            // 若首次佈局時機略晚，延遲再試一次，確保有一筆啟動診斷
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                logDiagIfReady()
            }
        }
        .onChange(of: isSelected) { _old, newValue in
            SimpleLogger.log("DEBUG: RankingRow.onChange isSelected=\(newValue) rank=\(item.rank)")
        }
        .onHover { over in
            withAnimation(.easeInOut(duration: 0.15)) { hovering = over }
            SimpleLogger.log("DEBUG: RankingRow.onHover over=\(over) rank=\(item.rank)")
        }
        .onTapGesture { isSelected = true }
        // 移除 swipeActions 以避免 macOS 列表在懸停/滑動時插入系統輔助視圖造成版面波動
        // 將狀態區與 hover 快捷動作改為 overlay，不參與 HStack 佈局
        .overlay(alignment: .trailing) {
            HStack(spacing: 8) {
                // 狀態區（始終顯示）
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
                        Button {
                            if let cb = onRequestPreview {
                                cb(preview)
                            } else {
                                #if canImport(AppKit)
                                NSWorkspace.shared.open(preview)
                                #endif
                            }
                        } label: {
                            Image(systemName: "play.circle.fill").font(compact ? .body : .title2).foregroundColor(.accentColor)
                        }
                    } else {
                        Image(systemName: "nosign").foregroundColor(.secondary)
                    }
                }
                .frame(width: trailingStatusWidth)

                // Hover 快捷動作（僅懸停顯示）
                if !compact {
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
                                if let cb = onRequestPreview {
                                    cb(preview)
                                } else {
                                    #if canImport(AppKit)
                                    NSWorkspace.shared.open(preview)
                                    #endif
                                }
                            } label: {
                                Image(systemName: "play.fill")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .frame(width: hoverWidth, alignment: .trailing)
                    .opacity(hovering ? 1 : 0)
                    .allowsHitTesting(hovering)
                    .animation(.easeInOut(duration: 0.15), value: hovering)
                }
            }
            .frame(width: reservedWidth, alignment: .trailing)
            // 記錄尾端 overlay 容器的左邊界（在列座標系），以對齊 trailing.minX
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        let minX = proxy.frame(in: .named("RankingRowCS-\(item.rank)")) .minX
                        diag_trailingMinX = minX
                    }
                    .onChange(of: proxy.size) { _old, _ in
                        let minX = proxy.frame(in: .named("RankingRowCS-\(item.rank)")) .minX
                        diag_trailingMinX = minX
                    }
            })
        }
    }

    private func logDiagIfReady() {
        guard !diag_loggedInitial else { return }
        var logged = false
        // 一、artworkRight 與 textLeft 的 12pt 固定間距驗證
        if let ax = diag_artworkMaxX, let tx = diag_textMinX {
            let delta = tx - ax
            SimpleLogger.log("DEBUG: RankingRow.layoutProbe rank=\(item.rank) artworkRight=\(String(format: "%.1f", ax)) textLeft=\(String(format: "%.1f", tx)) delta=\(String(format: "%.1f", delta)) expected=12.0")
            logged = true
        }
        // 二、比照使用者 INFO 欄位（main.maxX 與 trailing.minX）推導安全性
        if let mmx = diag_mainMaxX, let tmin = diag_trailingMinX {
            let guardSpacing: CGFloat = 12.0
            let gap = tmin - mmx
            let safe = gap >= guardSpacing
            SimpleLogger.log(String(format: "INFO: RowSafety rank=%d main.maxX=%.0f trailing.minX=%.0f gap=%.0f guard=%.0f safe=%@", item.rank, mmx, tmin, gap, guardSpacing, safe ? "true" : "false"))
            logged = true
        }
        if logged { diag_loggedInitial = true }
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
