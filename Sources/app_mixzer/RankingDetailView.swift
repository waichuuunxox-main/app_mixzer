// 根據 MusicRankingLogic.md 的邏輯設計
// Detail pane 顯示單一歌曲的豐富資訊（封面、專輯、發行日、預覽連結）
// 請勿在此播放音訊；Preview 以 Link 或系統播放器跳轉為主。
import SwiftUI

public struct RankingDetailView: View {
    public let item: RankingItem

    public init(item: RankingItem) {
        self.item = item
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let url = item.artworkURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.12))
                                .frame(height: 240)
                        case .success(let image):
                            image.resizable()
                                .scaledToFit()
                                .frame(maxHeight: 360)
                                .cornerRadius(12)
                                .shadow(radius: 6, y: 2)
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.25), value: item.artworkURL)
                        case .failure:
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.12))
                                .frame(height: 240)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }

                // Title & artist
                Text(item.title).font(.title).bold().accessibilityAddTraits(.isHeader)
                Text(item.artist).font(.title3).foregroundColor(.secondary)

                if let collection = item.collectionName {
                    Text(collection).font(.subheadline).foregroundColor(.secondary)
                }

                if let date = item.releaseDate {
                    Text("Released: \(RankingsView.dateFormatter.string(from: date))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

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
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle("\(item.rank). \(item.title)")
    }
}
