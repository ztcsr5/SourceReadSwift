import XCTest
@testable import SourceReadSwift

@MainActor
final class SettingsCacheLoadingTests: XCTestCase {
    func testChapterArchiveLoadsAwayFromInputThread() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let saved = ChapterContentCacheEntry(key: "source|chapter", sourceURL: "https://cache.invalid",
            chapterURL: "https://cache.invalid/chapter", bookURL: "https://cache.invalid/book",
            title: "章节", paragraphs: ["离线缓存应保留正文"], nextContentUrl: nil, purifySignature: "", cachedAt: Date())
        try ChapterContentCachePersistence(rootURL: root).save([saved])
        let store = await ChapterContentCacheStore.loadInBackground(
            persistence: ChapterContentCachePersistence(fileManager: BackgroundCacheReadFileManager(), rootURL: root))
        XCTAssertNil(store.lastError)
        XCTAssertEqual(store.entries.map(\.key), [saved.key])
        XCTAssertEqual(store.entries.first?.paragraphs, saved.paragraphs)
        XCTAssertGreaterThan(store.estimatedByteCount, 0)
    }

    func testConcurrentSettingsPreparationRetainsInjectedStoresAndSnapshots() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let chapter = ChapterContentCacheStore(preloadedEntries: .success([]))
        let feed = RSSFeedCacheStore(fileURL: root.appendingPathComponent("feed.json"), preloadedEntries: .success([
            RSSFeedCacheEntry(sourceURL: "https://kept.invalid", articles: [], cachedAt: Date())
        ]))
        let article = RSSArticleContentCacheStore(fileURL: root.appendingPathComponent("article.json"), preloadedEntries: .success([
            RSSArticleContentCacheEntry(articleID: "kept", paragraphs: ["原缓存"], cachedAt: Date())
        ]))
        let book = BookshelfBook(id: "settings-book", title: "书架", author: "纸间", coverURL: nil,
            sourceName: "本地", sourceURL: "local://text", bookURL: "local://settings-book", intro: nil)
        let app = AppState(sourceStore: SourceStore(preloadedSources: .success(SourceLibrarySnapshot())),
            bookshelfStore: BookshelfStore(preloadedBooks: .success([book]), preloadedGroups: .success([])),
            chapterContentCacheStore: chapter, rssFeedCacheStore: feed, rssArticleContentCacheStore: article)
        async let first: Void = app.prepareSettingsCaches()
        async let second: Void = app.prepareSettingsCaches()
        _ = await (first, second)
        XCTAssertTrue(app.chapterContentCacheStore === chapter)
        XCTAssertTrue(app.rssFeedCacheStore === feed)
        XCTAssertTrue(app.rssArticleContentCacheStore === article)
        XCTAssertEqual(app.rssFeedCacheStore.entries.first?.sourceURL, "https://kept.invalid")
        XCTAssertEqual(app.rssArticleContentCacheStore.entries.first?.paragraphs, ["原缓存"])
        await app.prepareSettingsCaches()
        XCTAssertTrue(app.rssArticleContentCacheStore === article)
        XCTAssertEqual(app.rssArticleContentCacheStore.entries.first?.paragraphs, ["原缓存"])
    }

    func testBackgroundChapterPreparationMatchesPrefetchLimitsAndKeepsOfflineDownloads() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = (0..<503).map { index in
            ChapterContentCacheEntry(key: "chapter-\(index)", sourceURL: "https://cache.invalid",
                chapterURL: "https://cache.invalid/chapter/\(index)", bookURL: "https://cache.invalid/book",
                title: "章节", paragraphs: ["正文"], nextContentUrl: nil, purifySignature: "", cachedAt: Date(),
                isOffline: index == 502)
        }
        let persistence = ChapterContentCachePersistence(rootURL: root)
        try persistence.save(entries)
        let synchronous = ChapterContentCacheStore(persistence: persistence)
        let background = await ChapterContentCacheStore.loadInBackground(persistence: persistence)
        XCTAssertEqual(background.entries.map(\.key), synchronous.entries.map(\.key))
        XCTAssertEqual(background.estimatedByteCount, synchronous.estimatedByteCount)
        XCTAssertEqual(background.entries.count, 501)
        XCTAssertTrue(background.entries.contains { $0.key == "chapter-502" && $0.isOffline == true })
    }

    func testRSSFactoriesRetainPersistedSnapshotsAndEntryLimits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let feedURL = root.appendingPathComponent("feed.json")
        let articleURL = root.appendingPathComponent("article.json")
        let feeds = RSSCacheFile<[RSSFeedCacheEntry]>(url: feedURL)
        feeds.save([RSSFeedCacheEntry(sourceURL: "https://one.invalid", articles: [], cachedAt: Date()),
            RSSFeedCacheEntry(sourceURL: "https://two.invalid", articles: [], cachedAt: Date())])
        let articles = RSSCacheFile<[RSSArticleContentCacheEntry]>(url: articleURL)
        articles.save([RSSArticleContentCacheEntry(articleID: "article", paragraphs: ["已保存"], cachedAt: Date())])
        let feedStore = await RSSFeedCacheStore.loadInBackground(fileURL: feedURL, maxSources: 1)
        let articleStore = await RSSArticleContentCacheStore.loadInBackground(fileURL: articleURL)
        XCTAssertEqual(feedStore.entries.map(\.sourceURL), ["https://one.invalid"])
        XCTAssertEqual(articleStore.entries.first?.paragraphs, ["已保存"])
    }
}

private final class BackgroundCacheReadFileManager: FileManager, @unchecked Sendable {
    override func fileExists(atPath path: String) -> Bool {
        XCTAssertFalse(Thread.isMainThread, "Preparing settings must not read chapter archives on MainActor")
        return super.fileExists(atPath: path)
    }
}
