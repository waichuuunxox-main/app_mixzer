import Foundation
import SwiftUI

#if canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#else
typealias PlatformImage = Image
#endif

actor ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSURL, ImageWrapper>()
    private init() {}

    private final class ImageWrapper: NSObject {
        let image: PlatformImage
        init(_ image: PlatformImage) { self.image = image }
    }

    nonisolated func uiImageFromData(_ data: Data) -> PlatformImage? {
        #if canImport(AppKit)
        return PlatformImage(data: data)
        #elseif canImport(UIKit)
        return PlatformImage(data: data)
        #else
        return nil
        #endif
    }

    func image(for url: URL) async -> PlatformImage? {
        let key = url as NSURL
        if let wrapped = cache.object(forKey: key) {
            // cache hit
            hitCount += 1
            SimpleLogger.log("ImageCache HIT for: \(url.absoluteString) (hits=\(hitCount), misses=\(missCount))")
            return wrapped.image
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = uiImageFromData(data) {
                let wrapped = ImageWrapper(img)
                cache.setObject(wrapped, forKey: key)
                missCount += 1
                SimpleLogger.log("ImageCache MISS for: \(url.absoluteString) (hits=\(hitCount), misses=\(missCount))")
                return img
            }
        } catch {
            return nil
        }

        return nil
    }

    // simple counters for hit/miss stats
    private var hitCount: Int = 0
    private var missCount: Int = 0

    func stats() -> (hits: Int, misses: Int) {
        return (hits: hitCount, misses: missCount)
    }

    /// Clear the in-memory cache and reset statistics.
    /// Use `await ImageCache.shared.clear()` from async contexts.
    func clear() {
        cache.removeAllObjects()
        hitCount = 0
        missCount = 0
        SimpleLogger.log("ImageCache cleared")
    }
}

struct CachedAsyncImage<Placeholder: View, Content: View>: View {
    let url: URL?
    let placeholder: Placeholder
    let content: (Image) -> Content

    @State private var platformImage: PlatformImage? = nil
    @State private var isLoaded: Bool = false

    init(url: URL?, @ViewBuilder placeholder: () -> Placeholder, @ViewBuilder content: @escaping (Image) -> Content) {
        self.url = url
        self.placeholder = placeholder()
        self.content = content
    }

    var body: some View {
        Group {
            if let platformImage = platformImage {
                #if canImport(AppKit)
                content(Image(nsImage: platformImage))
                    .opacity(isLoaded ? 1 : 0)
                    .animation(.easeIn(duration: 0.25), value: isLoaded)
                #elseif canImport(UIKit)
                content(Image(uiImage: platformImage))
                    .opacity(isLoaded ? 1 : 0)
                    .animation(.easeIn(duration: 0.25), value: isLoaded)
                #else
                placeholder
                #endif
            } else {
                placeholder
            }
        }
        // Debug overlay: when debug logging enabled, show the image URL and load state
        .overlay(alignment: .topLeading) {
            Group {
                // Only show the overlay when debug logging is enabled AND the
                // user has explicitly opted into the image debug overlay.
                if SimpleLogger.isDebug && UserDefaults.standard.bool(forKey: "showImageDebugOverlay") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url?.absoluteString ?? "<nil>")
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(isLoaded ? "loaded" : "idle")
                            .font(.caption2)
                    }
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(6)
                    .padding(6)
                }
            }
        }
        .onAppear {
            guard let url = url, platformImage == nil else { return }
            Task {
                let img = await ImageCache.shared.image(for: url)
                await MainActor.run {
                    self.platformImage = img
                    withAnimation(.easeIn(duration: 0.25)) { self.isLoaded = (img != nil) }
                }
            }
        }
        .onChange(of: url) { oldURL, newURL in
            // If the URL changed, reset and (re)load the new image.
            guard oldURL != newURL else { return }

            if let u = newURL {
                platformImage = nil
                isLoaded = false
                Task {
                    let img = await ImageCache.shared.image(for: u)
                    await MainActor.run {
                        self.platformImage = img
                        withAnimation(.easeIn(duration: 0.25)) { self.isLoaded = (img != nil) }
                    }
                }
            } else {
                // no url -> clear image
                platformImage = nil
                isLoaded = false
            }
        }
    }
}
