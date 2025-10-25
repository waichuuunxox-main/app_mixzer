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
                                .frame(maxHeight: 320)
                                .cornerRadius(12)
                        case .failure:
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.12))
                                .frame(height: 240)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }

                Text(item.title).font(.title).bold()
                Text(item.artist).font(.title3).foregroundColor(.secondary)

                if let collection = item.collectionName {
                    Text(collection).font(.subheadline).foregroundColor(.secondary)
                }

                if let date = item.releaseDate {
                    Text("Released: \(RankingsView.dateFormatter.string(from: date))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let preview = item.previewURL {
                    Link(destination: preview) {
                        Label("Open Preview", systemImage: "play.fill")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(8)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle("\(item.rank). \(item.title)")
    }
}
