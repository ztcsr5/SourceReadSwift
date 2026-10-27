import Foundation
import ImageIO
import UIKit

/// Shared in-memory image loader for remote covers and reader illustrations.
///
/// `CachedRemoteImage` and the TextKit reader surface both need the same
/// decoded bitmap for one URL, and illustrations often require the source's
/// own `Referer` / `User-Agent` before the CDN answers. Keeping one loader
/// avoids downloading the same illustration twice and makes the fetch
/// parameters explicit.
final class RemoteImageLoader: @unchecked Sendable {
    static let shared = RemoteImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    /// Covers are displayed at 50–150 pt but the source often serves a
    /// 1000 px JPEG. Keeping a separate downsampled cache avoids uploading a
    /// full-size texture for every shelf cell, which is the main reason the
    /// bookshelf and discover grids felt below ProMotion while scrolling.
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let inlineImages: InlineImageStore

    init(inlineImages: InlineImageStore = .shared) {
        self.inlineImages = inlineImages
        cache.countLimit = 160
        cache.totalCostLimit = 64 * 1024 * 1024
        thumbnailCache.countLimit = 240
        thumbnailCache.totalCostLimit = 32 * 1024 * 1024
    }

    /// Synchronous lookup for layout code that cannot await: a hit renders the
    /// real illustration immediately, a miss renders the placeholder and the
    /// async load fills it in afterwards.
    func cachedImage(for url: URL, maxPixelSize: CGFloat? = nil) -> UIImage? {
        if let maxPixelSize, maxPixelSize > 0 {
            return thumbnailCache.object(forKey: thumbnailKey(url, maxPixelSize))
        }
        return cache.object(forKey: url as NSURL)
    }

    /// Test hook and internal caching entry.
    func insert(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: url as NSURL, cost: max(cost, 1))
    }

    /// Test hook to clear cached images. In-flight downloads are cancelled so
    /// a cleared cache cannot be repopulated by a request that started earlier.
    func clearCache() {
        lock.lock()
        let pending = Array(inFlight.values)
        inFlight.removeAll()
        lock.unlock()
        for task in pending {
            task.cancel()
        }
        cache.removeAllObjects()
        thumbnailCache.removeAllObjects()
    }

    func image(
        for url: URL,
        headers: [String: String] = [:],
        maxPixelSize: CGFloat? = nil
    ) async -> UIImage? {
        if let cached = cachedImage(for: url, maxPixelSize: maxPixelSize) {
            return cached
        }
        if let maxPixelSize, maxPixelSize > 0,
           let full = cache.object(forKey: url as NSURL),
           let thumb = await Self.downsampleImageOffMainThread(full, maxPixelSize: maxPixelSize) {
            insertThumbnail(thumb, for: url, maxPixelSize: maxPixelSize)
            return thumb
        }

        let headerKey = headers.keys.sorted().map { "\($0):\(headers[$0] ?? "")" }.joined(separator: "|")
        let sizeKey = maxPixelSize.map { "px\(Int($0.rounded()))" } ?? "full"
        let cacheKey = url.absoluteString + "#" + headerKey + "#" + sizeKey

        lock.lock()
        if let existing = inFlight[cacheKey] {
            lock.unlock()
            return await existing.value
        }

        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            defer {
                self.lock.lock()
                self.inFlight.removeValue(forKey: cacheKey)
                self.lock.unlock()
            }
            return await self.download(url, headers: headers, maxPixelSize: maxPixelSize)
        }

        inFlight[cacheKey] = task
        lock.unlock()

        return await task.value
    }

    private func download(
        _ url: URL,
        headers: [String: String],
        maxPixelSize: CGFloat?
    ) async -> UIImage? {
        if InlineImageStore.isInlineURL(url) {
            guard let data = inlineImages.data(for: url) else { return nil }
            return await decodeAndStore(data, for: url, maxPixelSize: maxPixelSize)
        }

        // Locally imported EPUB covers are written into Application Support and
        // referenced with a file:// URL. URLSession answers a file request with a
        // plain URLResponse, so the HTTP-only guard below rejected every local
        // cover and the shelf/detail showed the placeholder forever.
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return await decodeAndStore(data, for: url, maxPixelSize: maxPixelSize)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        for (key, value) in headers where !key.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return nil }
            return await decodeAndStore(data, for: url, maxPixelSize: maxPixelSize)
        } catch {
            return nil
        }
    }

    private func decodeAndStore(
        _ data: Data,
        for url: URL,
        maxPixelSize: CGFloat?
    ) async -> UIImage? {
        if let maxPixelSize, maxPixelSize > 0 {
            guard let thumb = await Self.downsampleImageOffMainThread(data, maxPixelSize: maxPixelSize),
                  !Task.isCancelled else { return nil }
            insertThumbnail(thumb, for: url, maxPixelSize: maxPixelSize)
            return thumb
        }
        guard let decoded = await Self.decodeImageOffMainThread(data),
              !Task.isCancelled else { return nil }
        insert(decoded, for: url)
        return decoded
    }

    private func insertThumbnail(_ image: UIImage, for url: URL, maxPixelSize: CGFloat) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        thumbnailCache.setObject(
            image,
            forKey: thumbnailKey(url, maxPixelSize),
            cost: max(cost, 1)
        )
    }

    private func thumbnailKey(_ url: URL, _ maxPixelSize: CGFloat) -> NSString {
        "\(url.absoluteString)#px\(Int(maxPixelSize.rounded()))" as NSString
    }

    private static func downsampleImageOffMainThread(_ data: Data, maxPixelSize: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                autoreleasepool {
                    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceShouldCacheImmediately: true,
                        kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 32)
                    ]
                    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                        source,
                        0,
                        options as CFDictionary
                    ) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: UIImage(cgImage: cgImage))
                }
            }
        }
    }

    private static func downsampleImageOffMainThread(_ image: UIImage, maxPixelSize: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                autoreleasepool {
                    let sourcePixels = max(image.size.width, image.size.height) * image.scale
                    guard sourcePixels > maxPixelSize, maxPixelSize > 0 else {
                        continuation.resume(returning: image)
                        return
                    }
                    let ratio = maxPixelSize / sourcePixels
                    let target = CGSize(
                        width: max(image.size.width * ratio, 1),
                        height: max(image.size.height * ratio, 1)
                    )
                    let format = UIGraphicsImageRendererFormat.default()
                    format.scale = 1
                    format.opaque = false
                    let renderer = UIGraphicsImageRenderer(size: target, format: format)
                    let rendered = renderer.image { _ in
                        image.draw(in: CGRect(origin: .zero, size: target))
                    }
                    continuation.resume(returning: rendered)
                }
            }
        }
    }

    private static func decodeImageOffMainThread(_ data: Data) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                autoreleasepool {
                    guard let rawImage = UIImage(data: data) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let image = rawImage.preparingForDisplay() ?? rawImage
                    continuation.resume(returning: image)
                }
            }
        }
    }
}
