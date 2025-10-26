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
    // Track in-flight downloads to deduplicate network requests
    private var inFlight: [NSURL: Task<PlatformImage?, Never>] = [:]
    // Set a reasonable in-memory cost limit (bytes). Adjust as needed.
    // Here ~50 MB limit for image cache.
    nonisolated static let defaultMemoryLimit: Int = 50 * 1024 * 1024
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

    /// Load an image for the given URL. Downloads are deduplicated and decoding is
    /// performed off the actor to avoid blocking actor execution. A `maxPixelSize`
    /// hint is used to downsample large images for thumbnails which greatly
    /// improves memory and speed.
    // Maximum concurrent network downloads allowed
    private var activeDownloads: Int = 0
    nonisolated static let defaultMaxConcurrentDownloads: Int = 6

    func image(for url: URL, maxPixelSize: Int = 600) async -> PlatformImage? {
        let key = url as NSURL

        if let wrapped = cache.object(forKey: key) {
            // cache hit
            hitCount += 1
            SimpleLogger.log("ImageCache HIT for: \(url.absoluteString) (hits=\(hitCount), misses=\(missCount))")
            return wrapped.image
        }

        // If there's already an in-flight download, await it instead of starting
        // a new request.
        if let task = inFlight[key] {
            return await task.value
        }

        // Create a detached task to perform network + decode off this actor.
        let downloadTask = Task<PlatformImage?, Never> {
            do {
                // throttle global concurrent downloads (await until slot available)
                await acquireSlot()

                var req = URLRequest(url: url)
                req.timeoutInterval = 15
                let (data, _) = try await URLSession.shared.data(for: req)

                // Decode and downsample using Image I/O on a background thread.
                #if canImport(AppKit) || canImport(UIKit)
                if let cg = downsampledCGImage(from: data, maxPixelSize: maxPixelSize) {
                    #if canImport(AppKit)
                    let ns = PlatformImage(cgImage: cg, size: .zero)
                    return ns
                    #elseif canImport(UIKit)
                    let ui = PlatformImage(cgImage: cg)
                    return ui
                    #endif
                }
                #endif

                // Fallback to previous simple decoder
                return uiImageFromData(data)
            } catch {
                return nil
            }
        }

    inFlight[key] = downloadTask

        let result = await downloadTask.value

    // Cache and update stats on the actor
        if let img = result {
            // Charge cost by approximate memory: use pixel area * 4 (RGBA)
            let cost: Int = estimatedCostForImage(img)
            let wrapped = ImageWrapper(img)
            cache.totalCostLimit = ImageCache.defaultMemoryLimit
            cache.setObject(wrapped, forKey: key, cost: cost)
            missCount += 1
            SimpleLogger.log("ImageCache MISS for: \(url.absoluteString) (hits=\(hitCount), misses=\(missCount))")
        }

        // Clear inFlight slot
        inFlight[key] = nil

    // release throttle slot
    releaseSlot()

        return result
    }

    // Attempt small-first loading: try a small variant (if possible) for quick display,
    // then kick off a background fetch for the full image which will replace cache
    // when ready.
    func smallFirstImage(for url: URL, smallPixelSize: Int = 120, fullPixelSize: Int = 600) async -> PlatformImage? {
        // Try to derive a smaller variant URL (best-effort for iTunes artwork patterns)
        if let smallURL = smallVariantURL(for: url, targetPixel: smallPixelSize) {
            if let small = await image(for: smallURL, maxPixelSize: smallPixelSize) {
                // Kick off background fetch for the original URL (full-sized)
                Task.detached {
                    _ = await self.image(for: url, maxPixelSize: fullPixelSize)
                }
                return small
            }
        }

        // Fallback: load the original URL directly
        return await image(for: url, maxPixelSize: fullPixelSize)
    }

    // Try to convert known artwork URL patterns to a smaller size variant.
    nonisolated private func smallVariantURL(for url: URL, targetPixel: Int) -> URL? {
        let s = url.absoluteString
        // Match patterns like /1200x1200bb.jpg or /886449400515.jpg/1200x1200bb.jpg
        // We'll replace the first occurrence of NUMxNUMbb with targetPixelxtargetPixelbb when present.
        do {
            let pattern = "(\\d+)x(\\d+)(bb\\.(jpg|png))"
            let re = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let ns = s as NSString
            if re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) != nil {
                let newSize = "\(targetPixel)x\(targetPixel)bb.jpg"
                let newString = re.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: newSize)
                return URL(string: newString)
            }
        } catch {
            return nil
        }
        return nil
    }

    // Simple actors-side throttle helpers
    private func acquireSlot() async {
        while activeDownloads >= ImageCache.defaultMaxConcurrentDownloads {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        activeDownloads += 1
    }

    private func releaseSlot() {
        if activeDownloads > 0 { activeDownloads -= 1 }
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

    // MARK: - Helpers

    nonisolated private func estimatedCostForImage(_ image: PlatformImage) -> Int {
        #if canImport(AppKit)
        if let tiff = image.tiffRepresentation {
            return tiff.count
        }
        return 1
        #elseif canImport(UIKit)
        if let data = image.pngData() { return data.count }
        return 1
        #else
        return 1
        #endif
    }

    nonisolated private func downsampledCGImage(from data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [NSString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        let img = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        return img
    }
}

struct CachedAsyncImage<Placeholder: View, Content: View>: View {
    let url: URL?
    let placeholder: Placeholder
    let content: (Image) -> Content

    @State private var platformImage: PlatformImage? = nil
    @State private var isLoaded: Bool = false
    @State private var loadTask: Task<Void, Never>? = nil

    init(url: URL?, @ViewBuilder placeholder: () -> Placeholder, @ViewBuilder content: @escaping (Image) -> Content) {
        self.url = url
        self.placeholder = placeholder()
        self.content = content
    }

    var body: some View {
        Group {
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                #if canImport(AppKit)
                let scale = NSScreen.main?.backingScaleFactor ?? 1.0
                #elseif canImport(UIKit)
                let scale = UIScreen.main.scale
                #else
                let scale: CGFloat = 1.0
                #endif

                let maxDim = Int(max(width, height) * scale)

                ZStack {
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
                .onAppear {
                    guard let url = url, platformImage == nil else { return }
                    loadTask?.cancel()
                    let task = Task { @MainActor in
                        // Use dynamic maxPixelSize based on measured size; clamp to reasonable bounds
                        let pixelSize = max(64, min(1200, maxDim))
                        let img = await ImageCache.shared.smallFirstImage(for: url, smallPixelSize: 120, fullPixelSize: pixelSize)
                        self.platformImage = img
                        withAnimation(.easeIn(duration: 0.25)) { self.isLoaded = (img != nil) }
                    }
                    loadTask = task
                }
                .onChange(of: url) { oldURL, newURL in
                    guard oldURL != newURL else { return }
                    loadTask?.cancel()
                    if let u = newURL {
                        platformImage = nil
                        isLoaded = false
                        let task = Task { @MainActor in
                            let pixelSize = max(64, min(1200, maxDim))
                            let img = await ImageCache.shared.smallFirstImage(for: u, smallPixelSize: 120, fullPixelSize: pixelSize)
                            self.platformImage = img
                            withAnimation(.easeIn(duration: 0.25)) { self.isLoaded = (img != nil) }
                        }
                        loadTask = task
                    } else {
                        platformImage = nil
                        isLoaded = false
                    }
                }
                .onDisappear {
                    loadTask?.cancel()
                    loadTask = nil
                }
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
            // Cancel any previous task just in case
            loadTask?.cancel()
            let task = Task { @MainActor in
                let img = await ImageCache.shared.image(for: url, maxPixelSize: 300)
                self.platformImage = img
                withAnimation(.easeIn(duration: 0.25)) { self.isLoaded = (img != nil) }
            }
            loadTask = task
        }
        .onChange(of: url) { oldURL, newURL in
            // If the URL changed, reset and (re)load the new image.
            guard oldURL != newURL else { return }

            // cancel previous
            loadTask?.cancel()

            if let u = newURL {
                platformImage = nil
                isLoaded = false
                let task = Task { @MainActor in
                    let img = await ImageCache.shared.image(for: u, maxPixelSize: 300)
                    self.platformImage = img
                    withAnimation(.easeIn(duration: 0.25)) { self.isLoaded = (img != nil) }
                }
                loadTask = task
            } else {
                // no url -> clear image
                platformImage = nil
                isLoaded = false
            }
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }
}
