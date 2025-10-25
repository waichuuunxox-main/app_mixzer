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
            return wrapped.image
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = uiImageFromData(data) {
                let wrapped = ImageWrapper(img)
                cache.setObject(wrapped, forKey: key)
                return img
            }
        } catch {
            return nil
        }

        return nil
    }
}

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let placeholder: Placeholder
    let content: (Image) -> Image

    @State private var platformImage: PlatformImage? = nil

    init(url: URL?, @ViewBuilder placeholder: () -> Placeholder, @ViewBuilder content: @escaping (Image) -> Image = { $0 }) {
        self.url = url
        self.placeholder = placeholder()
        self.content = content
    }

    var body: some View {
        Group {
            if let platformImage = platformImage {
                #if canImport(AppKit)
                content(Image(nsImage: platformImage))
                #elseif canImport(UIKit)
                content(Image(uiImage: platformImage))
                #else
                placeholder
                #endif
            } else {
                placeholder
            }
        }
        .onAppear {
            guard let url = url, platformImage == nil else { return }
            Task {
                let img = await ImageCache.shared.image(for: url)
                self.platformImage = img
            }
        }
    }
}
