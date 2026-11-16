import XCTest
@testable import SourceReadSwift

@MainActor
final class ChapterContentCacheStoreTests: XCTestCase {
    func testPrefetchByteBudgetEvictsOlderChaptersWithoutTouchingExplicitDownloads() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChapterContentCacheStore(persistence: .init(rootURL: root), maxPrefetchBytes: 150)
        func content(_ index: Int, characters: Int) -> ChapterContent {
            let chapter = BookChapter(title: "Chapter", url: "https://book.invalid/\(index)",
                                      bookUrl: "https://book.invalid/title", index: index)
            return ChapterContent(chapter: chapter, title: chapter.title,
                                  paragraphs: [String(repeating: "x", count: characters)], nextContentUrl: nil)
        }
        let offline = content(0, characters: 200)
        let older = content(1, characters: 55)
        let recent = content(2, characters: 55)
        store.save(offline, sourceURL: "source", purifyRules: [], retainOffline: true)
        store.save(older, sourceURL: "source", purifyRules: [])
        store.save(recent, sourceURL: "source", purifyRules: [])
        XCTAssertNil(store.staleContent(sourceURL: "source", chapter: older.chapter))
        XCTAssertNotNil(store.staleContent(sourceURL: "source", chapter: recent.chapter))
        XCTAssertNotNil(store.staleContent(sourceURL: "source", chapter: offline.chapter))
    }

    func testRemovesLegacyUpdateOnlyChaptersAndDoesNotCacheNewOnes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = ChapterContentCachePersistence(rootURL: root)
        let sourceURL = "https://chapter.invalid"
        let chapterURL = "https://chapter.invalid/first"
        let bookURL = "https://chapter.invalid/book"
        let chapter = BookChapter(title: "第一章", url: chapterURL, bookUrl: bookURL, index: 0)
        let notice = "您的书源版本过低，请及时更新书源！点击登录进行书源更新。"
        let prose = "那一夜的风把窗台上的信吹到了院子里。"
        let entries = [
            ChapterContentCacheEntry(key: sourceURL + "|" + chapterURL, sourceURL: sourceURL,
                chapterURL: chapterURL, bookURL: bookURL, title: chapter.title, paragraphs: [notice, notice],
                nextContentUrl: nil, purifySignature: "", cachedAt: Date(), isOffline: true),
            ChapterContentCacheEntry(key: sourceURL + "|legitimate", sourceURL: sourceURL,
                chapterURL: "legitimate", bookURL: bookURL, title: "第二章", paragraphs: [prose],
                nextContentUrl: nil, purifySignature: "", cachedAt: Date(), isOffline: true)
        ]
        try persistence.save(entries)
        let store = ChapterContentCacheStore(persistence: persistence)
        XCTAssertNil(store.staleContent(sourceURL: sourceURL, chapter: chapter))
        store.save(ChapterContent(chapter: chapter, title: chapter.title, paragraphs: [notice], nextContentUrl: nil),
                   sourceURL: sourceURL, purifyRules: [])
        try await store.flush()
        XCTAssertEqual(try persistence.load().map(\.paragraphs), [[prose]])
    }

    func testPersistsChapterContentBySourceAndPurifySignature() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = ChapterContentCachePersistence(fileManager: .default, rootURL: root)
        let store = ChapterContentCacheStore(persistence: persistence)
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/chapter/1",
            bookUrl: "https://example.com/book",
            index: 0,
            isVip: false
        )
        let content = ChapterContent(
            chapter: chapter,
            title: "Chapter 1",
            paragraphs: ["A", "B"],
            nextContentUrl: nil
        )

        store.save(content, sourceURL: "https://source.example.com", purifyRules: ["广告.*##"])

        let reloaded = ChapterContentCacheStore(persistence: persistence)
        XCTAssertEqual(
            reloaded.content(
                sourceURL: "https://source.example.com",
                chapter: chapter,
                purifyRules: ["广告.*##"]
            )?.paragraphs,
            ["A", "B"]
        )
        XCTAssertNil(
            reloaded.content(
                sourceURL: "https://source.example.com",
                chapter: chapter,
                purifyRules: ["新的净化规则"]
            )
        )
        try? FileManager.default.removeItem(at: root)
    }

    func testRemoveAllPersists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = ChapterContentCachePersistence(fileManager: .default, rootURL: root)
        let store = ChapterContentCacheStore(persistence: persistence)
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/chapter/1",
            bookUrl: "https://example.com/book",
            index: 0,
            isVip: false
        )
        store.save(
            ChapterContent(chapter: chapter, title: "Chapter 1", paragraphs: ["A"], nextContentUrl: nil),
            sourceURL: "https://source.example.com",
            purifyRules: []
        )

        store.removeAll()

        let reloaded = ChapterContentCacheStore(persistence: persistence)
        XCTAssertTrue(reloaded.entries.isEmpty)
        try? FileManager.default.removeItem(at: root)
    }

    func testRemoveExpiredPersists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = ChapterContentCachePersistence(fileManager: .default, rootURL: root)
        try persistence.save([
            ChapterContentCacheEntry(
                key: "source|old",
                sourceURL: "source",
                chapterURL: "old",
                bookURL: "book",
                title: "Old",
                paragraphs: ["A"],
                nextContentUrl: nil,
                purifySignature: "",
                cachedAt: Date().addingTimeInterval(-40 * 24 * 60 * 60)
            ),
            ChapterContentCacheEntry(
                key: "source|new",
                sourceURL: "source",
                chapterURL: "new",
                bookURL: "book",
                title: "New",
                paragraphs: ["B"],
                nextContentUrl: nil,
                purifySignature: "",
                cachedAt: Date()
            )
        ])
        let store = ChapterContentCacheStore(persistence: persistence)

        store.removeExpired(olderThanDays: 30)

        XCTAssertEqual(store.entries.map(\.title), ["New"])
        let reloaded = ChapterContentCacheStore(persistence: persistence)
        XCTAssertEqual(reloaded.entries.map(\.title), ["New"])
        try? FileManager.default.removeItem(at: root)
    }

    func testCanReadStaleContentWhenPurifySignatureChanged() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = ChapterContentCachePersistence(fileManager: .default, rootURL: root)
        let store = ChapterContentCacheStore(persistence: persistence)
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/chapter/1",
            bookUrl: "https://example.com/book",
            index: 0,
            isVip: false
        )
        store.save(
            ChapterContent(chapter: chapter, title: "Chapter 1", paragraphs: ["cached"], nextContentUrl: nil),
            sourceURL: "https://source.example.com",
            purifyRules: ["old"]
        )

        XCTAssertNil(
            store.content(
                sourceURL: "https://source.example.com",
                chapter: chapter,
                purifyRules: ["new"]
            )
        )
        XCTAssertEqual(
            store.staleContent(sourceURL: "https://source.example.com", chapter: chapter)?.paragraphs,
            ["cached"]
        )
        try? FileManager.default.removeItem(at: root)
    }

    func testRemovesSingleEntryAndFiltersByBook() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let persistence = ChapterContentCachePersistence(fileManager: .default, rootURL: root)
        let store = ChapterContentCacheStore(persistence: persistence)
        let first = BookChapter(title: "One", url: "https://example.com/1", bookUrl: "book-a", index: 0, isVip: false)
        let second = BookChapter(title: "Two", url: "https://example.com/2", bookUrl: "book-b", index: 0, isVip: false)
        store.save(ChapterContent(chapter: first, title: "One", paragraphs: ["A"], nextContentUrl: nil), sourceURL: "source", purifyRules: [])
        store.save(ChapterContent(chapter: second, title: "Two", paragraphs: ["B"], nextContentUrl: nil), sourceURL: "source", purifyRules: [])
        XCTAssertEqual(store.entries(forBookURL: "book-a").map(\.title), ["One"])
        let key = try XCTUnwrap(store.entries.first?.key)
        store.remove(key: key)
        XCTAssertEqual(store.entries.count, 1)
        let reloaded = ChapterContentCacheStore(persistence: persistence)
        XCTAssertEqual(reloaded.entries.count, 1)
        try? FileManager.default.removeItem(at: root)
    }

    func testMarkReadMovesEntryToFrontAndPersists() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let persistence = ChapterContentCachePersistence(fileManager: .default, rootURL: root)
        let store = ChapterContentCacheStore(persistence: persistence)
        let first = BookChapter(title: "One", url: "https://example.com/1", bookUrl: "book", index: 0, isVip: false)
        let second = BookChapter(title: "Two", url: "https://example.com/2", bookUrl: "book", index: 1, isVip: false)
        store.save(ChapterContent(chapter: first, title: "One", paragraphs: ["A"], nextContentUrl: nil), sourceURL: "source", purifyRules: ["rule"])
        store.save(ChapterContent(chapter: second, title: "Two", paragraphs: ["B"], nextContentUrl: nil), sourceURL: "source", purifyRules: ["rule"])
        XCTAssertEqual(store.entries.map(\.title), ["Two", "One"])

        let readAt = Date().addingTimeInterval(60)
        store.markRead(sourceURL: "source", chapter: first, purifyRules: ["rule"], at: readAt)

        XCTAssertEqual(store.entries.map(\.title), ["One", "Two"])
        XCTAssertEqual(store.entries.first?.cachedAt.timeIntervalSince1970 ?? 0, readAt.timeIntervalSince1970, accuracy: 1)
        let reloaded = ChapterContentCacheStore(persistence: persistence)
        XCTAssertEqual(reloaded.entries.map(\.title), ["One", "Two"])
        try? FileManager.default.removeItem(at: root)
    }
}
