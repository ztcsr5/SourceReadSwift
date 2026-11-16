import SwiftUI
import UIKit

enum ReaderIllustratedBackgroundStore {
    private static let cache: ReaderIllustratedArtworkCache = {
        let cache = ReaderIllustratedArtworkCache(maximumCount: 4, maximumBytes: 32 * 1024 * 1024)
        // The cache has process lifetime; release its retained textures on pressure.
        _ = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                     object: nil, queue: nil) { [weak cache] _ in
            cache?.removeAll()
        }
        return cache
    }()
    private static let decoder = FullArtworkDecoder()
    private static let thumbnails: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 24
        return cache
    }()

    static func cached(_ name: String) -> UIImage? { cache.image(for: name) }

    static func cachedThumbnail(_ name: String) -> UIImage? { thumbnails.object(forKey: name as NSString) }

    static func loadThumbnail(_ name: String) async -> UIImage? {
        if let hit = cachedThumbnail(name) { return hit }
        return await Task.detached(priority: .utility) {
            // Keep the full-size artwork out of the carousel and its cache.
            let maximumDimension: CGFloat = 384
            guard let artwork = UIImage(named: name) else { return nil as UIImage? }
            let longest = max(artwork.size.width, artwork.size.height)
            guard longest > 0 else { return nil as UIImage? }
            let scale = min(maximumDimension / longest, 1)
            let size = CGSize(width: artwork.size.width * scale, height: artwork.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                artwork.draw(in: CGRect(origin: .zero, size: size))
            }
            thumbnails.setObject(thumbnail, forKey: name as NSString)
            return thumbnail
        }.value
    }

    /// Prepare bundled artwork away from the main actor while sharing concurrent loads.
    static func load(_ name: String) async -> UIImage? {
        if let hit = cached(name) { return hit }
        return await decoder.load(name)
    }

    private actor FullArtworkDecoder {
        func load(_ name: String) -> UIImage? {
            guard !Task.isCancelled else { return nil }
            if let hit = ReaderIllustratedBackgroundStore.cached(name) { return hit }
            guard let raw = UIImage(named: name) else { return nil }
            let decoded = raw.preparingForDisplay() ?? raw
            ReaderIllustratedBackgroundStore.cache.insert(decoded, for: name)
            return decoded
        }
    }
}

/// Holds the most recent full-size artwork under hard limits, unlike NSCache's advisory limits.
final class ReaderIllustratedArtworkCache: @unchecked Sendable {
    private struct Artwork {
        let name: String
        let image: UIImage
        let decodedBytes: Int
    }

    private let lock = NSLock()
    private let maximumCount: Int
    private let maximumBytes: Int
    private var oldestFirst: [Artwork] = []
    private var retainedBytes = 0

    init(maximumCount: Int, maximumBytes: Int) {
        self.maximumCount = max(0, maximumCount)
        self.maximumBytes = max(0, maximumBytes)
    }

    /// Look up a prepared image and mark it as the most recently used.
    func image(for name: String) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        guard let index = oldestFirst.firstIndex(where: { $0.name == name }) else { return nil }
        let hit = oldestFirst.remove(at: index)
        oldestFirst.append(hit)
        return hit.image
    }

    /// Retain only bitmaps that fit the budget; an oversized caller can still display its own image.
    func insert(_ image: UIImage, for name: String) {
        guard maximumCount > 0, let pixels = image.cgImage,
              pixels.height > 0, pixels.bytesPerRow <= maximumBytes / pixels.height else { return }
        let decodedBytes = pixels.bytesPerRow * pixels.height
        lock.lock()
        defer { lock.unlock() }
        if let index = oldestFirst.firstIndex(where: { $0.name == name }) {
            retainedBytes -= oldestFirst.remove(at: index).decodedBytes
        }
        while oldestFirst.count >= maximumCount || retainedBytes > maximumBytes - decodedBytes {
            retainedBytes -= oldestFirst.removeFirst().decodedBytes
        }
        oldestFirst.append(Artwork(name: name, image: image, decodedBytes: decodedBytes))
        retainedBytes += decodedBytes
    }

    /// Drop the cache's references without changing any currently mounted view.
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        oldestFirst.removeAll()
        retainedBytes = 0
    }
}

struct ReaderIllustratedSwatch: View {
    let name: String
    let paper: Color
    @State private var artwork: UIImage?

    var body: some View {
        ZStack {
            paper
            if let image = artwork ?? ReaderIllustratedBackgroundStore.cachedThumbnail(name) {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .frame(width: 66, height: 48)
        .clipped()
        .task(id: name) {
            let thumbnail = await ReaderIllustratedBackgroundStore.loadThumbnail(name)
            guard !Task.isCancelled else { return }
            artwork = thumbnail
        }
        .accessibilityHidden(true)
    }
}

struct ReaderIllustratedBackgroundView: View {
    let name: String
    let paper: Color
    let night: Bool
    var preservesNightArtwork: Bool = false
    @State private var image: UIImage?

    init(name: String, paper: Color, night: Bool = false, preservesNightArtwork: Bool = false) {
        self.name = name
        self.paper = paper
        self.night = night
        self.preservesNightArtwork = preservesNightArtwork
        _image = State(initialValue: ReaderIllustratedBackgroundStore.cached(name))
    }
    var body: some View {
        ZStack {
            paper
            if let image {
                ReaderWallpaperView(image: image, fillMode: .fill)
                    .opacity(night ? (preservesNightArtwork ? 0.86 : 0.14) : 1)
                if night && preservesNightArtwork {
                    paper.opacity(0.28)
                }
            }
        }
        .task(id: name) {
            let loaded = await ReaderIllustratedBackgroundStore.load(name)
            guard !Task.isCancelled else { return }
            image = loaded
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
