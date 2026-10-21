import Foundation
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
    private let lock = NSLock()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 160
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    /// Synchronous lookup for layout code that cannot await: a hit renders the
    /// real illustration immediately, a miss renders the placeholder and the
    /// async load fills it in afterwards.
    func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
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
    }

    func image(for url: URL, headers: [String: String] = [:]) async -> UIImage? {
        if let cached = cachedImage(for: url) {
            return cached
        }

        let headerKey = headers.keys.sorted().map { "\($0):\(headers[$0] ?? "")" }.joined(separator: "|")
        let cacheKey = url.absoluteString + "#" + headerKey

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
            return await self.download(url, headers: headers)
        }

        inFlight[cacheKey] = task
        lock.unlock()

        return await task.value
    }

    private func download(_ url: URL, headers: [String: String]) async -> UIImage? {
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

            guard let decoded = await Self.decodeImageOffMainThread(data),
                  !Task.isCancelled else { return nil }

            insert(decoded, for: url)
            return decoded
        } catch {
            return nil
        }
    }

    private static func decodeImageOffMainThread(_ data: Data) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                autoreleasepool {
                    continuation.resume(returning: UIImage(data: data)?.preparingForDisplay())
                }
            }
        }
    }
}
