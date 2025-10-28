import SwiftUI
import AVKit
import AVFoundation

/// A small embedded player view for macOS that wraps AVPlayerView.
/// Usage: include `EmbeddedPlayerView(url: url, isPresented: $isPresented, autoplay: true)` inside SwiftUI layout.
public struct EmbeddedPlayerView: View {
    let url: URL
    @Binding var isPresented: Bool
    var autoplay: Bool = true

    @State private var player: AVPlayer? = nil

    public init(url: URL, isPresented: Binding<Bool>, autoplay: Bool = true) {
        self.url = url
        self._isPresented = isPresented
        self.autoplay = autoplay
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            PlayerRepresentable(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .cornerRadius(8)

            HStack(spacing: 8) {
                Button(action: togglePlayPause) {
                    Image(systemName: (player?.timeControlStatus == .playing) ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderless)

                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
            }
            .padding(6)
        }
        .frame(height: 88)
        .onAppear {
            let item = AVPlayerItem(url: url)
            let p = AVPlayer(playerItem: item)
            self.player = p
            if autoplay { p.play() }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private func togglePlayPause() {
        guard let p = player else { return }
        if p.timeControlStatus == .playing { p.pause() } else { p.play() }
    }

    private func close() {
        player?.pause()
        player = nil
        isPresented = false
    }
}

fileprivate struct PlayerRepresentable: NSViewRepresentable {
    var player: AVPlayer?

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .minimal
        v.showsFullScreenToggleButton = false
        v.player = player
        return v
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}
