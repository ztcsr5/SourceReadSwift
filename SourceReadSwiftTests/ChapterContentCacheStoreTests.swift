import XCTest
@testable import SourceReadSwift

@MainActor
final class ChapterContentCacheStoreTests: XCTestCase {
    func testEstimatedBytesIncludeReviewAddressesAndOptionalCounts() throws {
        let first = try XCTUnwrap(URL(string: "https://fixture.invalid/review/1"))
        let second = try XCTUnwrap(URL(string: "https://fixture.invalid/review/2"))
        let entry = ChapterContentCacheEntry(key: "fixture", sourceURL: "https://fixture.invalid",
            chapterURL: "/chapter/1", bookURL: "/book/1", title: "题",
            paragraphs: ["字", "🙂"], nextContentUrl: nil,
            reviews: [.init(url: first, isChapter: false, count: "1万", paragraph: 0),
                      .init(url: second, isChapter: true, count: nil, paragraph: 0)],
            purifySignature: "", cachedAt: Date(timeIntervalSince1970: 0))
        let expected = ("题/chapter/1/book/1字🙂" + first.absoluteString + "1万" + second.absoluteString).utf8.count
        XCTAssertEqual(entry.estimatedByteCount, expected)
    }

    func testReplacementPolicyRejectsPurifiedCacheAndKeepsResultOverrideAfterReload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let preferenceName = "BookReplaceRuleCacheTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: preferenceName))
        defer { defaults.removePersistentDomain(forName: preferenceName) }
        let preferences = BookPurifyPreferenceStore(defaults: defaults)
        let persistence = ChapterContentCachePersistence(rootURL: root)
        let store = ChapterContentCacheStore(persistence: persistence, purifyPreferences: preferences)
        let source = "https://replace.invalid"
        let original = BookChapter(title: "Chapter", url: source + "/first/1", bookUrl: source + "/first", index: 0)
        let second = BookChapter(title: "Other", url: source + "/second/1", bookUrl: source + "/second", index: 0)
        let rules = ["广告##"]
        store.save(ChapterContent(chapter: original, title: original.title, paragraphs: ["净化后"]), sourceURL: source, purifyRules: rules)
        store.save(ChapterContent(chapter: second, title: second.title, paragraphs: ["另一本"]), sourceURL: source, purifyRules: rules)

        preferences.set(false, sourceURL: source, bookURL: original.bookUrl)
        XCTAssertNil(store.content(sourceURL: source, chapter: original, purifyRules: rules))
        XCTAssertNil(store.staleContent(sourceURL: source, chapter: original))
        XCTAssertFalse(store.cachedChapterURLs(sourceURL: source, purifyRules: rules, chapters: [original, second]).contains(original.url))
        XCTAssertNotNil(store.content(sourceURL: source, chapter: second, purifyRules: rules))

        let updated = original.withUseReplaceRule(false)
        store.save(ChapterContent(chapter: updated, title: updated.title, paragraphs: ["广告原文"]), sourceURL: source, purifyRules: rules)
        let reloaded = ChapterContentCacheStore(persistence: persistence,
            purifyPreferences: BookPurifyPreferenceStore(defaults: defaults))
        let restored = try XCTUnwrap(reloaded.content(sourceURL: source, chapter: original, purifyRules: ["新全局规则##"]))
        XCTAssertEqual(restored.paragraphs, ["广告原文"])
        XCTAssertEqual(restored.chapter.useReplaceRule, false)
        XCTAssertTrue(reloaded.cachedChapterURLs(sourceURL: source, purifyRules: [], chapters: [original]).contains(original.url))
        XCTAssertNil(reloaded.content(sourceURL: source + "/different-source", chapter: original, purifyRules: []))
        XCTAssertEqual(reloaded.cachedChapters(sourceURL: source, bookURL: original.bookUrl).first?.useReplaceRule, false)
    }

    func testComicDefaultPolicyIsStoredSeparatelyFromAuthoredOverride() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = ChapterContentCachePersistence(rootURL: root)
        let store = ChapterContentCacheStore(persistence: persistence)
        let chapter = BookChapter(title: "第1话", url: "https://comic.invalid/1", bookUrl: "https://comic.invalid/book",
            index: 0, mediaKind: .comic)
        store.save(ChapterContent(chapter: chapter, title: chapter.title, paragraphs: ["[img]https://comic.invalid/page.jpg[/img]"]),
            sourceURL: "comic", purifyRules: ["img##removed"])
        let reloaded = ChapterContentCacheStore(persistence: persistence)
        let cachedComic = try XCTUnwrap(reloaded.content(sourceURL: "comic", chapter: chapter, purifyRules: ["changed##"]))
        XCTAssertNil(cachedComic.chapter.useReplaceRule)
        XCTAssertFalse(cachedComic.chapter.usesGlobalPurifyRules)
        XCTAssertTrue(reloaded.cachedChapterURLs(sourceURL: "comic", purifyRules: []).contains(chapter.url))
        XCTAssertNil(reloaded.content(sourceURL: "comic", chapter: chapter.withUseReplaceRule(true), purifyRules: []))
    }

    func testDelayedPrefetchSaveDoesNotOverwriteNewerBookReplacementPreference() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let preferences = BookPurifyPreferenceStore()
        let store = ChapterContentCacheStore(persistence: .init(rootURL: root), purifyPreferences: preferences)
        let source = "https://replace.invalid"
        let staleChapter = BookChapter(title: "Chapter", url: source + "/first/1", bookUrl: source + "/first",
            index: 0, useReplaceRule: true)
        let otherChapter = BookChapter(title: "Other", url: source + "/second/1", bookUrl: source + "/second",
            index: 0, useReplaceRule: true)
        preferences.set(true, sourceURL: source, bookURL: otherChapter.bookUrl)
        preferences.set(false, sourceURL: source, bookURL: staleChapter.bookUrl)

        store.save(ChapterContent(chapter: staleChapter, title: staleChapter.title, paragraphs: ["旧净化结果"]),
            sourceURL: source, purifyRules: [])
        store.save(ChapterContent(chapter: otherChapter, title: otherChapter.title, paragraphs: ["另一本"]),
            sourceURL: source, purifyRules: [])

        XCTAssertEqual(preferences.value(sourceURL: source, bookURL: staleChapter.bookUrl), false)
        XCTAssertNil(store.content(sourceURL: source, chapter: staleChapter, purifyRules: []))
        XCTAssertNil(store.staleContent(sourceURL: source, chapter: staleChapter))
        XCTAssertEqual(preferences.value(sourceURL: source, bookURL: otherChapter.bookUrl), true)
        XCTAssertNotNil(store.content(sourceURL: source, chapter: otherChapter, purifyRules: []))
    }

    func testLegacyCacheRemainsReadableForDefaultOnBooksOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = ChapterContentCachePersistence(rootURL: root)
        let entry = ChapterContentCacheEntry(key: "source|chapter", sourceURL: "source", chapterURL: "chapter",
            bookURL: "book", title: "Chapter", paragraphs: ["正文"], nextContentUrl: nil, purifySignature: "", cachedAt: Date())
        let bytes = try JSONEncoder().encode(entry)
        let legacy = try JSONDecoder().decode(ChapterContentCacheEntry.self, from: bytes)
        XCTAssertNil(legacy.useReplaceRule)
        XCTAssertNil(legacy.usesGlobalPurifyRules)
        try persistence.save([legacy])
        let store = ChapterContentCacheStore(persistence: persistence)
        let chapter = BookChapter(title: "Chapter", url: "chapter", bookUrl: "book", index: 0)
        XCTAssertNotNil(store.content(sourceURL: "source", chapter: chapter, purifyRules: []))
        XCTAssertNil(store.content(sourceURL: "source", chapter: chapter.withUseReplaceRule(false), purifyRules: []))
    }

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

    func testRemovesLegacyRateLimitNoticesAndDoesNotCacheNewOnes() async throws {
        // Synthetic persisted notices cover migration of a bad cache entry.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = ChapterContentCachePersistence(rootURL: root)
        let sourceURL = "https://chapter.invalid"
        let chapter = BookChapter(title: "第一章", url: sourceURL + "/first", bookUrl: sourceURL + "/book", index: 0)
        let notice = "您的账号因访问过快已被暂时封禁，请在1分钟后重试。"
        let paidNotice = "本章为VIP章节，请登录后购买阅读。"
        let quotedStory = [notice, "他看完这行字，关掉屏幕，继续走向港口。"]
        let retained = [[paidNotice], quotedStory]
        try persistence.save([
            ChapterContentCacheEntry(key: sourceURL + "|" + chapter.url, sourceURL: sourceURL,
                chapterURL: chapter.url, bookURL: chapter.bookUrl, title: chapter.title, paragraphs: [notice],
                nextContentUrl: nil, purifySignature: "", cachedAt: Date(), isOffline: true)
        ] + retained.enumerated().map { index, paragraphs in
            ChapterContentCacheEntry(key: sourceURL + "|retained-\(index)", sourceURL: sourceURL,
                chapterURL: "retained-\(index)", bookURL: chapter.bookUrl, title: "第二章", paragraphs: paragraphs,
                nextContentUrl: nil, purifySignature: "", cachedAt: Date(), isOffline: true)
        })
        let store = ChapterContentCacheStore(persistence: persistence)
        XCTAssertNil(store.staleContent(sourceURL: sourceURL, chapter: chapter))
        store.save(ChapterContent(chapter: chapter, title: chapter.title,
            paragraphs: [notice, "也可以开通VIP解除访问限制。"], nextContentUrl: nil),
            sourceURL: sourceURL, purifyRules: [], retainOffline: true)
        XCTAssertNil(store.content(sourceURL: sourceURL, chapter: chapter, purifyRules: []))
        try await store.flush()
        XCTAssertEqual(try persistence.load().map(\.paragraphs), retained)
        XCTAssertEqual(ChapterContentCacheStore(persistence: persistence).entries.map(\.paragraphs), retained)
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
