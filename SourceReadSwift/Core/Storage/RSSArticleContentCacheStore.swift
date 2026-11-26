import Combine
import Foundation

struct RSSArticleContentCacheEntry: Codable, Hashable, Sendable {
    let articleID: String
    let paragraphs: [String]
    let contentHTML: String?
    let cachedAt: Date

    init(articleID: String, paragraphs: [String], contentHTML: String? = nil, cachedAt: Date) {
        self.articleID = articleID
        self.paragraphs = paragraphs
        self.contentHTML = contentHTML
        self.cachedAt = cachedAt
    }

    private enum CodingKeys: String, CodingKey { case articleID, paragraphs, contentHTML, cachedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        articleID = try c.decode(String.self, forKey: .articleID)
        paragraphs = try c.decode([String].self, forKey: .paragraphs)
        contentHTML = try c.decodeIfPresent(String.self, forKey: .contentHTML)
        cachedAt = try c.decode(Date.self, forKey: .cachedAt)
    }
}

@MainActor
final class RSSArticleContentCacheStore: ObservableObject {
    @Published private(set) var entries: [RSSArticleContentCacheEntry] = []

    private let fileURL: URL
    private let maxEntries: Int

    init(fileURL: URL? = nil, maxEntries: Int = 200, preloadedEntries: Result<[RSSArticleContentCacheEntry], Error>? = nil) {
        self.maxEntries = max(0, maxEntries)
        self.fileURL = Self.cacheURL(fileURL)
        do { entries = Array((try preloadedEntries?.get() ?? RSSCacheFile<[RSSArticleContentCacheEntry]>(url: self.fileURL).load() ?? []).prefix(self.maxEntries)) }
        catch { NSLog("RSS article cache read failed: code=%ld", (error as NSError).code) }
    }

    /// Reads persisted articles away from the navigation transaction.
    static func loadInBackground(fileURL: URL? = nil, maxEntries: Int = 200) async -> RSSArticleContentCacheStore {
        let restored = await Task.detached(priority: .utility) {
            let url = cacheURL(fileURL)
            return (url, Result { try RSSCacheFile<[RSSArticleContentCacheEntry]>(url: url).load() ?? [] })
        }.value
        return RSSArticleContentCacheStore(fileURL: restored.0, maxEntries: maxEntries, preloadedEntries: restored.1)
    }

    private nonisolated static func cacheURL(_ fileURL: URL?) -> URL {
        if let fileURL { return fileURL }
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SourceReadSwift/RSSArticleContentCache.json")
    }

    func paragraphs(for article: RSSArticlePreview, maxAge: TimeInterval? = nil) -> [String]? {
        guard let entry = entries.first(where: { article.stateIDs.contains($0.articleID) }) else { return nil }
        if let maxAge, Date().timeIntervalSince(entry.cachedAt) > maxAge { return nil }
        return entry.paragraphs
    }

    func contentHTML(for article: RSSArticlePreview, maxAge: TimeInterval? = nil) -> String? {
        guard let entry = entries.first(where: { article.stateIDs.contains($0.articleID) }) else { return nil }
        if let maxAge, Date().timeIntervalSince(entry.cachedAt) > maxAge { return nil }
        return entry.contentHTML
    }

    func cachedAt(for article: RSSArticlePreview) -> Date? {
        entries.first(where: { article.stateIDs.contains($0.articleID) })?.cachedAt
    }

    func isStale(for article: RSSArticlePreview, maxAge: TimeInterval = RSSFeedCacheStore.defaultMaxAge) -> Bool {
        guard let cachedAt = cachedAt(for: article) else { return false }
        return Date().timeIntervalSince(cachedAt) > max(0, maxAge)
    }

    func save(_ paragraphs: [String], for article: RSSArticlePreview, contentHTML: String? = nil) {
        let normalized = paragraphs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return }
        let entry = RSSArticleContentCacheEntry(articleID: article.id, paragraphs: normalized, contentHTML: contentHTML, cachedAt: Date())
        entries.removeAll { article.stateIDs.contains($0.articleID) }
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        persist()
    }

    func remove(articleID: String) {
        entries.removeAll { $0.articleID == articleID }
        persist()
    }

    func removeAll() {
        entries.removeAll()
        persist()
    }

    private func persist() {
        RSSCacheFile<[RSSArticleContentCacheEntry]>(url: fileURL).save(entries)
    }

    func waitForPendingWrites() async { await RSSCacheFile<[RSSArticleContentCacheEntry]>(url: fileURL).waitForPendingWrites() }
}
