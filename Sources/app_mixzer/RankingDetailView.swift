// 根據 MusicRankingLogic.md 的邏輯設計
// Detail pane 顯示單一歌曲的豐富資訊（封面、專輯、發行日、預覽連結）
// 請勿在此播放音訊；Preview 以 Link 或系統播放器跳轉為主。
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

fileprivate let detailDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    return f
}()

public struct RankingDetailView: View {
    public let item: RankingItem
    let namespace: Namespace.ID
    // whether this detail is currently selected (controls matchedGeometry isSource)
    let isSelected: Bool

    public init(item: RankingItem, namespace: Namespace.ID, isSelected: Bool = true) {
        self.item = item
        self.namespace = namespace
        self.isSelected = isSelected
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Artwork card with material background and improved animation
                if let url = item.artworkURL {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.regularMaterial)
                            .frame(height: 380)
                            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)

                        CachedAsyncImage(url: url) {
                            // skeleton / placeholder
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.12))
                                .frame(height: 340)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.06))
                                )
                                .redacted(reason: .placeholder)
                        } content: { img in
                img
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 340)
                                .clipped()
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
                                .opacity(0.98)
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                                .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.75, blendDuration: 0.15), value: item.artworkURL)
                                .matchedGeometryEffect(id: "artwork-\(item.rank)", in: namespace, properties: .frame, anchor: .center, isSource: isSelected)
                        }
                        .padding(16)
                        .id(url.absoluteString)
                    }
                    .padding(.horizontal, 6)
                }

                // Title & artist (participate in matchedGeometry transitions)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.system(.title, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                        .matchedGeometryEffect(id: "title-\(item.rank)", in: namespace)

                    Text(item.artist)
                        .font(.system(.title3))
                        .foregroundColor(.secondary)
                        .matchedGeometryEffect(id: "artist-\(item.rank)", in: namespace)
                }
                .padding(.horizontal, 10)

                // Metadata card
                VStack(alignment: .leading, spacing: 8) {
                    if let collection = item.collectionName {
                        HStack {
                            Label("Album", systemImage: "rectangle.stack.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        Text(collection)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }

                    if let date = item.releaseDate {
                        HStack {
                            Label("Released", systemImage: "calendar")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        Text("\(detailDateFormatter.string(from: date))")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }

                    Divider()

                    HStack(spacing: 12) {
                        if let preview = item.previewURL {
                            Link(destination: preview) {
                                Label("Open Preview", systemImage: "play.fill")
                                    .font(.headline)
                                    .padding(10)
                                    .background(Color.accentColor.opacity(0.12))
                                    .cornerRadius(8)
                            }
                        }

                        // Copy metadata button
                        Button {
                            #if canImport(AppKit)
                            let paste = NSPasteboard.general
                            paste.clearContents()
                            let text = "\(item.title) — \(item.artist)\n\(item.collectionName ?? "")"
                            paste.setString(text, forType: .string)
                            #endif
                        } label: {
                            Label("Copy info", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: NSColor.controlBackgroundColor)))
                .padding(.horizontal, 6)

                Spacer(minLength: 40)
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationTitle("\(item.rank). \(item.title)")
        .onAppear {
            SimpleLogger.log("DEBUG: RankingDetailView.onAppear rank=\(item.rank)")
        }
        .onDisappear {
            SimpleLogger.log("DEBUG: RankingDetailView.onDisappear rank=\(item.rank)")
        }
    }
}
