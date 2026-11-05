import Foundation
import CryptoKit
import ImageIO
import UIKit

enum ComicImageFailure: Error, Equatable, Sendable {
    case http(Int), timedOut, invalidResponse, emptyResponse, invalidImage, tooLarge, network, cancelled

    var canRefreshAddress: Bool {
        switch self {
        case .http(403), .http(404), .http(410), .http(422): return true
        default: return false
        }
    }

    var message: String {
        switch self {
        case .http(403): return "图片访问被拒绝，可检查书源登录状态后重试。"
        case .http(404), .http(410): return "图片地址已失效，可重试或换源。"
        case .http(422): return "书源未接受图片请求，可重试或换源。"
        case .http(let status): return "图片请求失败（HTTP \(status)）。"
        case .timedOut: return "图片请求超时，可重试。"
        case .emptyResponse: return "书源返回了空图片，可重试。"
        case .invalidResponse, .invalidImage: return "书源未返回可显示的图片。"
        case .tooLarge: return "图片超出安全加载大小。"
        case .network: return "无法连接到图片服务器。"
        case .cancelled: return "图片请求已取消。"
        }
    }
}

/// Shared in-memory image loader for remote covers and reader illustrations.
///
/// `CachedRemoteImage` and the TextKit reader surface both need the same
/// decoded bitmap for one URL, and illustrations often require the source's
/// own `Referer` / `User-Agent` before the CDN answers. Keeping one loader
/// avoids downloading the same illustration twice and makes the fetch
/// parameters explicit.
final class RemoteImageLoader: @unchecked Sendable {
    static let shared = RemoteImageLoader()
    private static let boundedSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    private let cache = NSCache<NSURL, UIImage>()
    /// Covers are displayed at 50–150 pt but the source often serves a
    /// 1000 px JPEG. Keeping a separate downsampled cache avoids uploading a
    /// full-size texture for every shelf cell, which is the main reason the
    /// bookshelf and discover grids felt below ProMotion while scrolling.
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private struct ComicFlight {
        let id: UUID
        let task: Task<Result<UIImage, ComicImageFailure>, Never>
        var readers: Set<UUID>
    }
    private struct ComicResource {
        let url: URL
        let headers: [String: String]
        let maxPixelSize: CGFloat
    }
    private var comicInFlight: [String: ComicFlight] = [:]
    private let comicBudget = ComicImageBudget()
    private let coverSources = CoverSourceBytes()
    private let inlineImages: InlineImageStore
    private let session: URLSession

    init(inlineImages: InlineImageStore = .shared, session: URLSession? = nil) {
        self.inlineImages = inlineImages
        self.session = session ?? Self.boundedSession
        cache.countLimit = 160
        cache.totalCostLimit = 64 * 1024 * 1024
        thumbnailCache.countLimit = 240
        thumbnailCache.totalCostLimit = 32 * 1024 * 1024
    }

    /// Synchronous lookup for layout code that cannot await: a hit renders the
    /// real illustration immediately, a miss renders the placeholder and the
    /// async load fills it in afterwards.
    func cachedImage(for url: URL, maxPixelSize: CGFloat? = nil, reuseCoverBytes: Bool = false,
                     headers: [String: String] = [:]) -> UIImage? {
        let identity = imageCacheURL(url, headers: headers)
        if let maxPixelSize, maxPixelSize > 0 {
            return thumbnailCache.object(forKey: thumbnailKey(identity, maxPixelSize, isCover: reuseCoverBytes && headers.isEmpty))
        }
        return cache.object(forKey: identity as NSURL)
    }

    private func imageCacheURL(_ url: URL, headers: [String: String]) -> URL {
        guard !headers.isEmpty else { return url }
        let fields = headers.sorted { $0.key < $1.key }.map { "\($0.key.count):\($0.key)\($0.value.count):\($0.value)" }
        let fingerprint = SHA256.hash(data: Data((url.absoluteString + "|" + fields.joined()).utf8))
            .map { String(format: "%02x", $0) }.joined()
        return URL(string: "sourceread-image-context://" + fingerprint)!
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
        let pendingComic = comicInFlight.values.map(\.task)
        inFlight.removeAll()
        comicInFlight.removeAll()
        lock.unlock()
        for task in pending {
            task.cancel()
        }
        for task in pendingComic { task.cancel() }
        cache.removeAllObjects()
        thumbnailCache.removeAllObjects()
        coverSources.clear()
    }

    /// Share a decoded page only with the exact image request context.
    func comicPage(for url: URL, headers: [String: String], maxPixelSize: CGFloat) async -> Result<UIImage, ComicImageFailure> {
        guard !Task.isCancelled else { return .failure(.cancelled) }
        let key = comicKey(url, headers: headers, maxPixelSize: maxPixelSize)
        if let image = thumbnailCache.object(forKey: key as NSString) { return .success(image) }
        let reader = UUID()
        let resource = ComicResource(url: url, headers: headers, maxPixelSize: maxPixelSize)
        let flight = acquireComicPage(key: key, resource: resource, reader: reader)
        return await withTaskCancellationHandler(operation: {
            let result = await flight.task.value
            releaseComicPage(key: key, flight: flight.id, reader: reader)
            return Task.isCancelled ? .failure(.cancelled) : result
        }, onCancel: {
            self.releaseComicPage(key: key, flight: flight.id, reader: reader)
        })
    }

    func cachedComicPage(for url: URL, headers: [String: String], maxPixelSize: CGFloat) -> UIImage? {
        thumbnailCache.object(forKey: comicKey(url, headers: headers, maxPixelSize: maxPixelSize) as NSString)
    }

    /// Test probe for shared-request cancellation; does not expose request headers.
    func comicSubscriberCount(for url: URL, headers: [String: String], maxPixelSize: CGFloat) -> Int {
        let key = comicKey(url, headers: headers, maxPixelSize: maxPixelSize)
        lock.lock()
        defer { lock.unlock() }
        return comicInFlight[key]?.readers.count ?? 0
    }

    private func comicKey(_ url: URL, headers: [String: String], maxPixelSize: CGFloat) -> String {
        let fields = headers.sorted { $0.key < $1.key }.map { "\($0.key.count):\($0.key)\($0.value.count):\($0.value)" }
        return "comic|\(url.absoluteString.count):\(url.absoluteString)|\(Int(maxPixelSize))|" + fields.joined()
    }

    private func acquireComicPage(key: String, resource: ComicResource, reader: UUID) -> ComicFlight {
        lock.lock()
        defer { lock.unlock() }
        if var existing = comicInFlight[key] {
            existing.readers.insert(reader)
            comicInFlight[key] = existing
            return existing
        }
        let id = UUID()
        let task = Task<Result<UIImage, ComicImageFailure>, Never> { [self] in
            let permit = UUID()
            guard await comicBudget.acquire(permit) else {
                finishComicPage(key: key, flight: id, result: .failure(.cancelled))
                return .failure(.cancelled)
            }
            let result = await downloadComicPage(resource.url, headers: resource.headers, maxPixelSize: resource.maxPixelSize)
            await comicBudget.release(permit)
            finishComicPage(key: key, flight: id, result: result)
            return result
        }
        let flight = ComicFlight(id: id, task: task, readers: [reader])
        comicInFlight[key] = flight
        return flight
    }

    private func releaseComicPage(key: String, flight: UUID, reader: UUID) {
        lock.lock()
        guard var active = comicInFlight[key], active.id == flight,
              active.readers.remove(reader) != nil else { lock.unlock(); return }
        let shouldCancel = active.readers.isEmpty
        if shouldCancel { comicInFlight.removeValue(forKey: key) }
        else { comicInFlight[key] = active }
        lock.unlock()
        if shouldCancel { active.task.cancel() }
    }

    private func finishComicPage(key: String, flight: UUID, result: Result<UIImage, ComicImageFailure>) {
        lock.lock()
        defer { lock.unlock() }
        guard comicInFlight[key]?.id == flight else { return }
        comicInFlight.removeValue(forKey: key)
        guard !Task.isCancelled else { return }
        if case .success(let image) = result {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            thumbnailCache.setObject(image, forKey: key as NSString, cost: max(cost, 1))
        }
    }

    /// Offline downloads use the same authenticated transport as visible pages.
    func comicBytesForArchive(_ request: ComicImageRequest) async -> Result<Data, ComicImageFailure> {
        guard let url = URL(string: request.url), !url.isFileURL else { return .failure(.invalidResponse) }
        return await fetchComicBytes(url, headers: request.headers).map(\.bytes)
    }

    private struct ComicTransfer {
        let bytes: Data
        let request: URLRequest?
    }

    private func fetchComicBytes(_ url: URL, headers: [String: String]) async -> Result<ComicTransfer, ComicImageFailure> {
        guard !Task.isCancelled else { return .failure(.cancelled) }
        if InlineImageStore.isInlineURL(url) {
            guard let bytes = inlineImages.data(for: url) else { return .failure(.invalidImage) }
            return .success(.init(bytes: bytes, request: nil))
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return .failure(.invalidResponse) }
        var request = URLRequest(url: url, timeoutInterval: 18)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        do {
            let (bytes, response) = try await session.data(for: request)
            guard !Task.isCancelled else { return .failure(.cancelled) }
            guard let http = response as? HTTPURLResponse else { return .failure(.invalidResponse) }
            guard (200..<300).contains(http.statusCode) else {
                session.configuration.urlCache?.removeCachedResponse(for: request)
                return .failure(.http(http.statusCode))
            }
            guard !bytes.isEmpty else {
                session.configuration.urlCache?.removeCachedResponse(for: request)
                return .failure(.emptyResponse)
            }
            guard bytes.count <= ComicOfflineArchive.maximumPageBytes else { return .failure(.tooLarge) }
            return .success(.init(bytes: bytes, request: request))
        } catch let error as URLError {
            if error.code == .cancelled { return .failure(.cancelled) }
            return .failure(error.code == .timedOut ? .timedOut : .network)
        } catch { return .failure(.network) }
    }

    private func downloadComicPage(_ url: URL, headers: [String: String], maxPixelSize: CGFloat) async -> Result<UIImage, ComicImageFailure> {
        let transfer: ComicTransfer
        if url.isFileURL {
            // External rules cannot produce file URLs; only verified offline/local imports supply them.
            guard let bytes = try? Data(contentsOf: url, options: .mappedIfSafe),
                  !bytes.isEmpty, bytes.count <= ComicOfflineArchive.maximumPageBytes else { return .failure(.invalidImage) }
            transfer = .init(bytes: bytes, request: nil)
        } else {
            switch await fetchComicBytes(url, headers: headers) {
            case .success(let loaded): transfer = loaded
            case .failure(let failure): return .failure(failure)
            }
        }
        guard !Task.isCancelled else { return .failure(.cancelled) }
        guard let image = await Self.downsampleImageOffMainThread(transfer.bytes, maxPixelSize: maxPixelSize) else {
            if let request = transfer.request { session.configuration.urlCache?.removeCachedResponse(for: request) }
            return .failure(.invalidImage)
        }
        return .success(image)
    }

    func image(
        for url: URL,
        headers: [String: String] = [:],
        maxPixelSize: CGFloat? = nil,
        reuseCoverBytes: Bool = false
    ) async -> UIImage? {
        let isCover = reuseCoverBytes && headers.isEmpty && (maxPixelSize ?? 0) > 0
        if let cached = cachedImage(for: url, maxPixelSize: maxPixelSize, reuseCoverBytes: isCover, headers: headers) {
            return cached
        }
        let identity = imageCacheURL(url, headers: headers)
        if !isCover, let maxPixelSize, maxPixelSize > 0,
           let full = cache.object(forKey: identity as NSURL),
           let thumb = await Self.downsampleImageOffMainThread(full, maxPixelSize: maxPixelSize) {
            insertThumbnail(thumb, for: identity, maxPixelSize: maxPixelSize)
            return thumb
        }

        let headerKey = headers.keys.sorted().map { "\($0):\(headers[$0] ?? "")" }.joined(separator: "|")
        let sizeKey = maxPixelSize.map { "px\(Int($0.rounded()))" } ?? "full"
        let cacheKey = (isCover ? "cover|" : "image|") + url.absoluteString + "#" + headerKey + "#" + sizeKey

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
            return await self.download(url, headers: headers, maxPixelSize: maxPixelSize,
                reuseCoverBytes: isCover)
        }

        inFlight[cacheKey] = task
        lock.unlock()

        return await task.value
    }

    private func download(
        _ url: URL,
        headers: [String: String],
        maxPixelSize: CGFloat?,
        reuseCoverBytes: Bool
    ) async -> UIImage? {
        let identity = imageCacheURL(url, headers: headers)
        if InlineImageStore.isInlineURL(url) {
            guard let data = inlineImages.data(for: url) else { return nil }
            return await decodeAndStore(data, for: identity, maxPixelSize: maxPixelSize, isCover: reuseCoverBytes)
        }

        // Locally imported EPUB covers are written into Application Support and
        // referenced with a file:// URL. URLSession answers a file request with a
        // plain URLResponse, so the HTTP-only guard below rejected every local
        // cover and the shelf/detail showed the placeholder forever.
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return await decodeAndStore(data, for: identity, maxPixelSize: maxPixelSize, isCover: reuseCoverBytes)
        }

        let bytes: Data?
        if reuseCoverBytes {
            bytes = await coverSources.bytes(for: url) { [self] in await fetchImageBytes(url, headers: [:]) }
        } else {
            bytes = await fetchImageBytes(url, headers: headers)?.bytes
        }
        guard let bytes, !Task.isCancelled else { return nil }
        let image = await decodeAndStore(bytes, for: identity, maxPixelSize: maxPixelSize, isCover: reuseCoverBytes)
        if image == nil, reuseCoverBytes, !Task.isCancelled { coverSources.invalidate(url, matching: bytes) }
        return image
    }

    private func fetchImageBytes(_ url: URL, headers: [String: String]) async -> CoverSourceBytes.Response? {
        var request = URLRequest(url: url, timeoutInterval: 18)
        request.cachePolicy = headers.isEmpty ? .useProtocolCachePolicy : .reloadIgnoringLocalCacheData
        for (key, value) in headers where !key.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                // A cached 403/expired signed response must not make the
                // reader's explicit retry replay the same failure forever.
                session.configuration.urlCache?.removeCachedResponse(for: request)
                return nil
            }
            let directives = (http.value(forHTTPHeaderField: "Cache-Control") ?? "").lowercased()
            let freshness = CoverSourceBytes.freshness(cacheControl: directives,
                age: http.value(forHTTPHeaderField: "Age"),
                hasExplicitExpiry: http.value(forHTTPHeaderField: "Expires") != nil)
            return CoverSourceBytes.Response(bytes: data, freshness: freshness)
        } catch {
            return nil
        }
    }

    private func decodeAndStore(
        _ data: Data,
        for url: URL,
        maxPixelSize: CGFloat?,
        isCover: Bool
    ) async -> UIImage? {
        if let maxPixelSize, maxPixelSize > 0 {
            guard let thumb = await Self.downsampleImageOffMainThread(data, maxPixelSize: maxPixelSize),
                  !Task.isCancelled else { return nil }
            insertThumbnail(thumb, for: url, maxPixelSize: maxPixelSize, isCover: isCover)
            return thumb
        }
        guard let decoded = await Self.decodeImageOffMainThread(data),
              !Task.isCancelled else { return nil }
        insert(decoded, for: url)
        return decoded
    }

    private func insertThumbnail(_ image: UIImage, for url: URL, maxPixelSize: CGFloat, isCover: Bool = false) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        thumbnailCache.setObject(
            image,
            forKey: thumbnailKey(url, maxPixelSize, isCover: isCover),
            cost: max(cost, 1)
        )
    }

    private func thumbnailKey(_ url: URL, _ maxPixelSize: CGFloat, isCover: Bool) -> NSString {
        "\(isCover ? "cover" : "image")|\(url.absoluteString)#px\(Int(maxPixelSize.rounded()))" as NSString
    }

    private static func downsampleImageOffMainThread(_ data: Data, maxPixelSize: CGFloat) async -> UIImage? {
        await decodeBitmap {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 32)
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: cgImage)
        }
    }

    private static func downsampleImageOffMainThread(_ image: UIImage, maxPixelSize: CGFloat) async -> UIImage? {
        await decodeBitmap {
            let sourcePixels = max(image.size.width, image.size.height) * image.scale
            guard sourcePixels > maxPixelSize, maxPixelSize > 0 else { return image }
            let ratio = maxPixelSize / sourcePixels
            let target = CGSize(width: max(image.size.width * ratio, 1), height: max(image.size.height * ratio, 1))
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = false
            return UIGraphicsImageRenderer(size: target, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: target))
            }
        }
    }

    private static func decodeImageOffMainThread(_ data: Data) async -> UIImage? {
        await decodeBitmap {
            guard let rawImage = UIImage(data: data) else { return nil }
            return rawImage.preparingForDisplay() ?? rawImage
        }
    }

    // Covers and comic pages share CPU capacity, but not transfer permits.
    // Two decoders leave cores available for UIKit/WebKit while retaining resolution.
    private static let bitmapBudget = ComicImageBudget(limit: 2)

    static func decodeBitmap(_ decode: @escaping @Sendable () -> UIImage?) async -> UIImage? {
        let permit = UUID()
        guard await bitmapBudget.acquire(permit) else { return nil }
        guard !Task.isCancelled else { await bitmapBudget.release(permit); return nil }
        let bitmap: UIImage? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: autoreleasepool(invoking: decode))
            }
        }
        await bitmapBudget.release(permit)
        return Task.isCancelled ? nil : bitmap
    }
}
