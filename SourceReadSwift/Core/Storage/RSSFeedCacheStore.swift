import Foundation
import Combine

struct RSSFeedCacheEntry: Codable, Hashable, Sendable {
    let sourceURL: String
    let articles: [RSSArticlePreview]
    let cachedAt: Date
}

@MainActor
final class RSSFeedCacheStore: ObservableObject {
    static let defaultMaxAge: TimeInterval = 7 * 24 * 60 * 60
    @Published private(set) var entries: [RSSFeedCacheEntry] = []
    private let fileURL: URL
    private let maxSources: Int

    init(fileURL: URL? = nil, maxSources: Int = 50, preloadedEntries: Result<[RSSFeedCacheEntry], Error>? = nil) {
        self.maxSources = max(0, maxSources)
        self.fileURL = Self.cacheURL(fileURL)
        do { entries = Array((try preloadedEntries?.get() ?? RSSCacheFile<[RSSFeedCacheEntry]>(url: self.fileURL).load() ?? []).prefix(self.maxSources)) }
        catch { NSLog("RSS feed cache read failed: code=%ld", (error as NSError).code) }
    }

    /// Reads persisted articles away from the navigation transaction.
    static func loadInBackground(fileURL: URL? = nil, maxSources: Int = 50) async -> RSSFeedCacheStore {
        let restored = await Task.detached(priority: .utility) {
            let url = cacheURL(fileURL)
            return (url, Result { try RSSCacheFile<[RSSFeedCacheEntry]>(url: url).load() ?? [] })
        }.value
        return RSSFeedCacheStore(fileURL: restored.0, maxSources: maxSources, preloadedEntries: restored.1)
    }

    private nonisolated static func cacheURL(_ fileURL: URL?) -> URL {
        if let fileURL { return fileURL }
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SourceReadSwift/RSSFeedCache.json")
    }

    func articles(for sourceURL: String, maxAge: TimeInterval? = nil) -> [RSSArticlePreview]? {
        guard let entry = entries.first(where: { $0.sourceURL == sourceURL }) else { return nil }
        if let maxAge, Date().timeIntervalSince(entry.cachedAt) > maxAge { return nil }
        return entry.articles
    }

    func cachedAt(for sourceURL: String) -> Date? {
        entries.first(where: { $0.sourceURL == sourceURL })?.cachedAt
    }

    func isStale(sourceURL: String, maxAge: TimeInterval = RSSFeedCacheStore.defaultMaxAge) -> Bool {
        guard let cachedAt = cachedAt(for: sourceURL) else { return false }
        return Date().timeIntervalSince(cachedAt) > max(0, maxAge)
    }

    func save(_ articles: [RSSArticlePreview], sourceURL: String) {
        let entry = RSSFeedCacheEntry(sourceURL: sourceURL, articles: Array(articles.prefix(100)), cachedAt: Date())
        entries.removeAll { $0.sourceURL == sourceURL }
        entries.insert(entry, at: 0)
        if entries.count > maxSources { entries.removeLast(entries.count - maxSources) }
        persist()
    }

    func remove(sourceURL: String) {
        entries.removeAll { $0.sourceURL == sourceURL }
        persist()
    }

    func removeAll() {
        entries.removeAll()
        persist()
    }

    private func persist() {
        RSSCacheFile<[RSSFeedCacheEntry]>(url: fileURL).save(entries)
    }

    func waitForPendingWrites() async { await RSSCacheFile<[RSSFeedCacheEntry]>(url: fileURL).waitForPendingWrites() }
}
