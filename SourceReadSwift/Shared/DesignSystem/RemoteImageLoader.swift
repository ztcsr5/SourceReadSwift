import Foundation
import CryptoKit
import ImageIO
import UIKit

enum ComicImageFailure: Error, Equatable, Sendable {
    case http(Int), timedOut, invalidResponse, emptyResponse, invalidImage, imageDecodeFailed, tooLarge, network, cancelled

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
        case .imageDecodeFailed: return "图片解码规则执行失败，可检查书源版本后重试。"
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
    private static func boundedConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = ComicImageTimeoutPolicy.defaultRequest
        configuration.timeoutIntervalForResource = ComicImageTimeoutPolicy.defaultResource
        return configuration
    }

    private struct Routing {
        let configuration: URLSessionConfiguration
        var session: URLSession? = nil
        var proxyConfiguration: (@Sendable () -> SourceProxyConfiguration)? = nil
        var observer: (@Sendable (ComicImageTransportObservation) -> Void)? = nil
    }

    private final class Transport: @unchecked Sendable {
        let id = UUID()
        let proxyConfiguration: SourceProxyConfiguration?
        let session: URLSession
        let comic: ComicImageTransport
        let covers = CoverSourceBytes()
        private let ownsSession: Bool

        init(configuration: URLSessionConfiguration, session: URLSession?, proxyConfiguration: SourceProxyConfiguration?,
             observer: (@Sendable (ComicImageTransportObservation) -> Void)?) {
            guard let configuration = configuration.copy() as? URLSessionConfiguration else {
                preconditionFailure("URLSessionConfiguration must produce a configuration copy")
            }
            if let proxyConfiguration { configuration.connectionProxyDictionary = proxyConfiguration.connectionProxyDictionary }
            self.proxyConfiguration = proxyConfiguration
            self.session = session ?? URLSession(configuration: configuration)
            self.comic = ComicImageTransport(configuration: configuration, observer: observer)
            self.ownsSession = session == nil
        }

        deinit { if ownsSession { session.finishTasksAndInvalidate() } }
    }

    private let cache = NSCache<NSURL, UIImage>()
    /// Covers are displayed at 50–150 pt but the source often serves a
    /// 1000 px JPEG. Keeping a separate downsampled cache avoids uploading a
    /// full-size texture for every shelf cell, which is the main reason the
    /// bookshelf and discover grids felt below ProMotion while scrolling.
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private struct ImageFlight {
        let id: UUID
        let task: Task<UIImage?, Never>
        let transport: Transport
    }
    private var inFlight: [String: ImageFlight] = [:]
    private struct ImageRequest: Sendable {
        let headers: [String: String]
        let maxPixelSize: CGFloat?
        let isCover: Bool
        var coverFill: CoverFillRaster? = nil
    }
    private struct ComicFlight {
        let id: UUID
        let task: Task<Result<UIImage, ComicImageFailure>, Never>
        var readers: Set<UUID>
    }
    private struct ComicResource {
        let url: URL
        let headers: [String: String]
        let maxPixelSize: CGFloat
        let decodeContext: SourceImageDecodeContext?
        let transport: Transport
    }
    private var comicInFlight: [String: ComicFlight] = [:]
    private let comicBudget = ComicImageBudget()
    private let inlineImages: InlineImageStore
    private let routing: Routing
    private var activeTransport: Transport

    convenience init(inlineImages: InlineImageStore = .shared, session: URLSession? = nil,
         configuration: URLSessionConfiguration? = nil,
         comicTransportObserver: (@Sendable (ComicImageTransportObservation) -> Void)? = nil) {
        let followsProxy = session == nil && configuration == nil
        let proxyProvider: (@Sendable () -> SourceProxyConfiguration)?
        if followsProxy { proxyProvider = { SourceProxyConfiguration.load(from: .standard) } }
        else { proxyProvider = nil }
        self.init(inlineImages: inlineImages, routing: Routing(
            configuration: configuration ?? session?.configuration ?? Self.boundedConfiguration(), session: session,
            proxyConfiguration: proxyProvider,
            observer: comicTransportObserver))
    }

    /// Inject a route store without changing process-wide settings or URL loading fixtures.
    convenience init(configuration: URLSessionConfiguration,
                     proxyConfigurationProvider: @escaping @Sendable () -> SourceProxyConfiguration,
                     comicTransportObserver: (@Sendable (ComicImageTransportObservation) -> Void)? = nil) {
        self.init(inlineImages: .shared, routing: Routing(configuration: configuration,
            proxyConfiguration: proxyConfigurationProvider, observer: comicTransportObserver))
    }

    private init(inlineImages: InlineImageStore, routing: Routing) {
        self.inlineImages = inlineImages
        self.routing = routing
        self.activeTransport = Transport(configuration: routing.configuration, session: routing.session,
            proxyConfiguration: routing.proxyConfiguration?(), observer: routing.observer)
        cache.countLimit = 160
        cache.totalCostLimit = 64 * 1024 * 1024
        thumbnailCache.countLimit = 240
        thumbnailCache.totalCostLimit = 32 * 1024 * 1024
    }

    private func currentTransport() -> Transport {
        lock.lock()
        defer { lock.unlock() }
        if let updated = routing.proxyConfiguration?(), updated != activeTransport.proxyConfiguration {
            // New requests switch together; existing requests retain their original route.
            activeTransport = Transport(configuration: routing.configuration, session: nil,
                proxyConfiguration: updated, observer: routing.observer)
        }
        return activeTransport
    }

    /// Test probe of the actual URLSession configurations, without exposing image headers.
    func proxyRouteSnapshot() -> (id: UUID, images: [AnyHashable: Any]?, comics: [AnyHashable: Any]?) {
        let transport = currentTransport()
        return (transport.id, transport.session.configuration.connectionProxyDictionary, transport.comic.connectionProxyDictionary)
    }

    /// Synchronous lookup for layout code that cannot await: a hit renders the
    /// real illustration immediately, a miss renders the placeholder and the
    /// async load fills it in afterwards.
    func cachedImage(for url: URL, maxPixelSize: CGFloat? = nil, reuseCoverBytes: Bool = false,
                     headers: [String: String] = [:]) -> UIImage? {
        let identity = imageCacheURL(url, headers: headers)
        if let maxPixelSize, maxPixelSize > 0 {
            return thumbnailCache.object(forKey: thumbnailKey(identity, maxPixelSize, isCover: reuseCoverBytes))
        }
        return cache.object(forKey: identity as NSURL)
    }

    /// A large, cropped cover uses a distinct entry from all longest-edge thumbnails.
    func cachedCoverImage(for url: URL, filling target: CoverFillRaster, headers: [String: String] = [:]) -> UIImage? {
        thumbnailCache.object(forKey: coverFillKey(imageCacheURL(url, headers: headers), target))
    }

    /// Share the original encoded bytes with the small shelf, but decode for the hero's frame.
    func coverImage(for url: URL, filling target: CoverFillRaster, headers: [String: String] = [:]) async -> UIImage? {
        await image(for: url, request: .init(headers: headers, maxPixelSize: nil, isCover: true, coverFill: target))
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
        let coverTransports = [activeTransport] + pending.map(\.transport)
        let pendingComic = comicInFlight.values.map(\.task)
        inFlight.removeAll()
        comicInFlight.removeAll()
        lock.unlock()
        for flight in pending {
            flight.task.cancel()
        }
        for task in pendingComic { task.cancel() }
        cache.removeAllObjects()
        thumbnailCache.removeAllObjects()
        for transport in coverTransports { transport.covers.clear() }
    }

    /// Share a decoded page only with the exact image request context.
    func comicPage(for url: URL, headers: [String: String], maxPixelSize: CGFloat,
                   decodeContext: SourceImageDecodeContext? = nil) async -> Result<UIImage, ComicImageFailure> {
        guard !Task.isCancelled else { return .failure(.cancelled) }
        let key = comicKey(url, headers: headers, maxPixelSize: maxPixelSize, decodeContext: decodeContext)
        if let image = thumbnailCache.object(forKey: key as NSString) { return .success(image) }
        let transport = currentTransport()
        let flightKey = transport.id.uuidString + "|" + key
        let reader = UUID()
        let resource = ComicResource(url: url, headers: headers, maxPixelSize: maxPixelSize,
                                     decodeContext: decodeContext, transport: transport)
        let flight = acquireComicPage(key: flightKey, resource: resource, reader: reader)
        return await withTaskCancellationHandler(operation: {
            let result = await flight.task.value
            releaseComicPage(key: flightKey, flight: flight.id, reader: reader)
            return Task.isCancelled ? .failure(.cancelled) : result
        }, onCancel: {
            self.releaseComicPage(key: flightKey, flight: flight.id, reader: reader)
        })
    }

    func cachedComicPage(for url: URL, headers: [String: String], maxPixelSize: CGFloat,
                         decodeContext: SourceImageDecodeContext? = nil) -> UIImage? {
        thumbnailCache.object(forKey: comicKey(url, headers: headers, maxPixelSize: maxPixelSize, decodeContext: decodeContext) as NSString)
    }

    /// Test probe for shared-request cancellation; does not expose request headers.
    func comicSubscriberCount(for url: URL, headers: [String: String], maxPixelSize: CGFloat,
                              decodeContext: SourceImageDecodeContext? = nil) -> Int {
        let key = currentTransport().id.uuidString + "|" + comicKey(url, headers: headers, maxPixelSize: maxPixelSize, decodeContext: decodeContext)
        lock.lock()
        defer { lock.unlock() }
        return comicInFlight[key]?.readers.count ?? 0
    }

    private func comicKey(_ url: URL, headers: [String: String], maxPixelSize: CGFloat,
                          decodeContext: SourceImageDecodeContext?) -> String {
        let fields = headers.sorted { $0.key < $1.key }.map { "\($0.key.count):\($0.key)\($0.value.count):\($0.value)" }
        return "comic|\(url.absoluteString.count):\(url.absoluteString)|\(Int(maxPixelSize))|\(decodeContext?.fingerprint ?? "raw")|" + fields.joined()
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
            let transfer: ComicTransfer
            if resource.url.isFileURL {
                guard let bytes = try? Data(contentsOf: resource.url, options: .mappedIfSafe),
                      !bytes.isEmpty, bytes.count <= ComicOfflineArchive.maximumPageBytes else {
                    finishComicPage(key: key, flight: id, resource: resource, result: .failure(.invalidImage))
                    return .failure(.invalidImage)
                }
                transfer = .init(bytes: bytes, request: nil)
            } else {
                let permit = UUID()
                guard await comicBudget.acquire(permit) else {
                    finishComicPage(key: key, flight: id, resource: resource, result: .failure(.cancelled))
                    return .failure(.cancelled)
                }
                let loaded = await fetchComicBytes(resource.url, headers: resource.headers,
                    decodeContext: resource.decodeContext, transport: resource.transport)
                await comicBudget.release(permit)
                switch loaded {
                case .success(let value): transfer = value
                case .failure(let failure):
                    finishComicPage(key: key, flight: id, resource: resource, result: .failure(failure))
                    return .failure(failure)
                }
            }
            guard !Task.isCancelled else {
                finishComicPage(key: key, flight: id, resource: resource, result: .failure(.cancelled))
                return .failure(.cancelled)
            }
            let result: Result<UIImage, ComicImageFailure>
            if let image = await Self.downsampleImageOffMainThread(transfer.bytes, maxPixelSize: resource.maxPixelSize,
                                                                   preservesComicWidth: true) {
                result = .success(image)
            } else {
                if let request = transfer.request { resource.transport.session.configuration.urlCache?.removeCachedResponse(for: request) }
                result = .failure(.invalidImage)
            }
            finishComicPage(key: key, flight: id, resource: resource, result: result)
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

    private func finishComicPage(key: String, flight: UUID, resource: ComicResource,
                                 result: Result<UIImage, ComicImageFailure>) {
        lock.lock()
        defer { lock.unlock() }
        guard comicInFlight[key]?.id == flight else { return }
        comicInFlight.removeValue(forKey: key)
        guard !Task.isCancelled else { return }
        if case .success(let image) = result {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            let cacheKey = comicKey(resource.url, headers: resource.headers, maxPixelSize: resource.maxPixelSize,
                                    decodeContext: resource.decodeContext)
            thumbnailCache.setObject(image, forKey: cacheKey as NSString, cost: max(cost, 1))
        }
    }

    /// Offline downloads use the same authenticated transport as visible pages.
    func comicBytesForArchive(_ request: ComicImageRequest) async -> Result<Data, ComicImageFailure> {
        guard let url = URL(string: request.url), !url.isFileURL else { return .failure(.invalidResponse) }
        let permit = UUID()
        guard await comicBudget.acquire(permit) else { return .failure(.cancelled) }
        let result = await fetchComicBytes(url, headers: request.headers, decodeContext: request.decodeContext,
                                          transport: currentTransport()).map(\.bytes)
        await comicBudget.release(permit)
        return result
    }

    private struct ComicTransfer {
        let bytes: Data
        let request: URLRequest?
    }

    private func fetchComicBytes(_ url: URL, headers: [String: String],
                                 decodeContext: SourceImageDecodeContext?, transport: Transport) async -> Result<ComicTransfer, ComicImageFailure> {
        guard !Task.isCancelled else { return .failure(.cancelled) }
        if InlineImageStore.isInlineURL(url) {
            guard let bytes = inlineImages.data(for: url) else { return .failure(.invalidImage) }
            guard bytes.count <= ComicOfflineArchive.maximumPageBytes else { return .failure(.tooLarge) }
            return .success(.init(bytes: bytes, request: nil))
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return .failure(.invalidResponse) }
        var request = URLRequest(url: url, timeoutInterval: ComicImageTimeoutPolicy.defaultRequest)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let result = await transport.comic.load(request)
        if case .failure(let error) = result, error != .cancelled {
            transport.session.configuration.urlCache?.removeCachedResponse(for: request)
        }
        switch result {
        case .failure(let failure): return .failure(failure)
        case .success(let bytes):
            guard let decodeContext else { return .success(.init(bytes: bytes, request: request)) }
            return await SourceImageByteDecoder.decode(bytes, sourceURL: url, context: decodeContext)
                .map { .init(bytes: $0, request: request) }
        }
    }

    private func downloadComicPage(_ url: URL, headers: [String: String], maxPixelSize: CGFloat,
                                    decodeContext: SourceImageDecodeContext?) async -> Result<UIImage, ComicImageFailure> {
        let transport = currentTransport()
        let transfer: ComicTransfer
        if url.isFileURL {
            // External rules cannot produce file URLs; only verified offline/local imports supply them.
            guard let bytes = try? Data(contentsOf: url, options: .mappedIfSafe),
                  !bytes.isEmpty, bytes.count <= ComicOfflineArchive.maximumPageBytes else { return .failure(.invalidImage) }
            transfer = .init(bytes: bytes, request: nil)
        } else {
            switch await fetchComicBytes(url, headers: headers, decodeContext: decodeContext, transport: transport) {
            case .success(let loaded): transfer = loaded
            case .failure(let failure): return .failure(failure)
            }
        }
        guard !Task.isCancelled else { return .failure(.cancelled) }
        guard let image = await Self.downsampleImageOffMainThread(transfer.bytes, maxPixelSize: maxPixelSize,
                                                                preservesComicWidth: true) else {
            if let request = transfer.request { transport.session.configuration.urlCache?.removeCachedResponse(for: request) }
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
        let isCover = reuseCoverBytes && (maxPixelSize ?? 0) > 0
        return await image(for: url, request: .init(headers: headers, maxPixelSize: maxPixelSize, isCover: isCover))
    }

    private func image(for url: URL, request: ImageRequest) async -> UIImage? {
        let headers = request.headers
        let isCover = request.isCover
        let maxPixelSize = request.maxPixelSize
        if let target = request.coverFill {
            if let cached = cachedCoverImage(for: url, filling: target, headers: headers) { return cached }
        } else if let cached = cachedImage(for: url, maxPixelSize: maxPixelSize, reuseCoverBytes: isCover, headers: headers) {
            return cached
        }
        let identity = imageCacheURL(url, headers: headers)
        if !isCover, let maxPixelSize, maxPixelSize > 0,
           let full = cache.object(forKey: identity as NSURL),
           let thumb = await Self.downsampleImageOffMainThread(full, maxPixelSize: maxPixelSize) {
            insertThumbnail(thumb, for: identity, maxPixelSize: maxPixelSize)
            return thumb
        }

        let sizeKey = request.coverFill?.cacheSize ?? maxPixelSize.map { "px\(Int($0.rounded()))" } ?? "full"
        let transport = currentTransport()
        let cacheKey = transport.id.uuidString + "|" + (isCover ? "cover|" : "image|") + identity.absoluteString + "#" + sizeKey

        lock.lock()
        if let existing = inFlight[cacheKey] {
            lock.unlock()
            return await existing.task.value
        }

        let id = UUID()
        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            defer {
                self.lock.lock()
                if self.inFlight[cacheKey]?.id == id { self.inFlight.removeValue(forKey: cacheKey) }
                self.lock.unlock()
            }
            return await self.download(url, request: request, transport: transport)
        }

        inFlight[cacheKey] = ImageFlight(id: id, task: task, transport: transport)
        lock.unlock()

        return await task.value
    }

    private func download(_ url: URL, request: ImageRequest, transport: Transport) async -> UIImage? {
        let headers = request.headers
        let identity = imageCacheURL(url, headers: headers)
        if InlineImageStore.isInlineURL(url) {
            guard let data = inlineImages.data(for: url) else { return nil }
            return await decodeAndStore(data, for: identity, request: request)
        }

        // Locally imported EPUB covers are written into Application Support and
        // referenced with a file:// URL. URLSession answers a file request with a
        // plain URLResponse, so the HTTP-only guard below rejected every local
        // cover and the shelf/detail showed the placeholder forever.
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return await decodeAndStore(data, for: identity, request: request)
        }

        let bytes: Data?
        if request.isCover {
            bytes = await transport.covers.bytes(for: identity) { [self] in
                await fetchImageBytes(url, headers: headers, transport: transport)
            }
        } else {
            bytes = await fetchImageBytes(url, headers: headers, transport: transport)?.bytes
        }
        guard let bytes, !Task.isCancelled else { return nil }
        let image = await decodeAndStore(bytes, for: identity, request: request)
        if image == nil, request.isCover, !Task.isCancelled { transport.covers.invalidate(identity, matching: bytes) }
        return image
    }

    private func fetchImageBytes(_ url: URL, headers: [String: String], transport: Transport) async -> CoverSourceBytes.Response? {
        var request = URLRequest(url: url, timeoutInterval: 18)
        request.cachePolicy = headers.isEmpty ? .useProtocolCachePolicy : .reloadIgnoringLocalCacheData
        for (key, value) in headers where !key.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await transport.session.data(for: request)
            guard !Task.isCancelled,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                // A cached 403/expired signed response must not make the
                // reader's explicit retry replay the same failure forever.
                transport.session.configuration.urlCache?.removeCachedResponse(for: request)
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
        request: ImageRequest
    ) async -> UIImage? {
        if let target = request.coverFill {
            guard let cover = await Self.downsampleImageOffMainThread(data, coverFill: target),
                  !Task.isCancelled else { return nil }
            insertThumbnail(cover, key: coverFillKey(url, target))
            return cover
        }
        if let maxPixelSize = request.maxPixelSize, maxPixelSize > 0 {
            guard let thumb = await Self.downsampleImageOffMainThread(data, maxPixelSize: maxPixelSize),
                  !Task.isCancelled else { return nil }
            insertThumbnail(thumb, for: url, maxPixelSize: maxPixelSize, isCover: request.isCover)
            return thumb
        }
        guard let decoded = await Self.decodeImageOffMainThread(data),
              !Task.isCancelled else { return nil }
        insert(decoded, for: url)
        return decoded
    }

    private func insertThumbnail(_ image: UIImage, for url: URL, maxPixelSize: CGFloat, isCover: Bool = false) {
        insertThumbnail(image, key: thumbnailKey(url, maxPixelSize, isCover: isCover))
    }

    private func insertThumbnail(_ image: UIImage, key: NSString) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        thumbnailCache.setObject(image, forKey: key, cost: max(cost, 1))
    }

    private func thumbnailKey(_ url: URL, _ maxPixelSize: CGFloat, isCover: Bool) -> NSString {
        "\(isCover ? "cover" : "image")|\(url.absoluteString)#px\(Int(maxPixelSize.rounded()))" as NSString
    }

    private func coverFillKey(_ url: URL, _ target: CoverFillRaster) -> NSString {
        "cover|\(url.absoluteString)#\(target.cacheSize)" as NSString
    }

    private static func fittedCoverLimit(_ target: CoverFillRaster, source: CGImageSource) -> CGFloat {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = CGFloat((properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0)
        let height = CGFloat((properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0)
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapsAxes = (5...8).contains(orientation)
        return target.maximumPixelSize(orientedWidth: swapsAxes ? height : width, orientedHeight: swapsAxes ? width : height)
    }

    private static func downsampleImageOffMainThread(_ data: Data, maxPixelSize: CGFloat = 32,
                                                     preservesComicWidth: Bool = false,
                                                     coverFill: CoverFillRaster? = nil) async -> UIImage? {
        await decodeBitmap {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
            var dimension = max(maxPixelSize, 32)
            if let coverFill {
                dimension = fittedCoverLimit(coverFill, source: source)
            } else if preservesComicWidth, maxPixelSize >= 4096,
               let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
               let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
               width > 0, height > width * 3 {
                // A fixed longest edge shrank 1000x16000 text to 256 pixels wide.
                // Keep up to 1280 pixels across, bounded to 8 Mi pixels / 16384 high.
                let scale = min(1, 1280 / width, sqrt((8 * 1024 * 1024) / (width * height)), 16384 / height)
                dimension = CGFloat(height * scale)
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: dimension
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
