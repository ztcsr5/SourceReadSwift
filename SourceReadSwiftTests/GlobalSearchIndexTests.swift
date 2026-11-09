import XCTest
@testable import SourceReadSwift

final class GlobalSearchIndexTests: XCTestCase {
    func testCancelledSearchDoesNotContinueScanningTheCatalog() async {
        let result = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return GlobalSearchIndex.search("主题", entries: GlobalSearchIndex.settings)
        }.value
        XCTAssertTrue(result.isEmpty)
    }
    @MainActor func testAggregateComicHistoryRetainsMediaKindAfterDiskReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = ReadingHistoryPersistence(rootURL: root)
        let history = ReadingHistoryStore(persistence: persistence)
        let book = BookshelfBook(searchBook: SearchBook(name: "聚合漫画", author: nil, coverUrl: nil,
            bookUrl: "https://fixture.invalid/comic", sourceName: "聚合源", sourceUrl: "https://fixture.invalid",
            mediaKind: .comic))
        history.record(book: book)
        await history.waitForPendingWrites()
        let restored = try XCTUnwrap(persistence.load().first)
        XCTAssertEqual(restored.asSearchBook.mediaKind, .comic)
        XCTAssertEqual(restored.asBookshelfBook.mediaKind, .comic)
    }

    func testEmptyAndWhitespaceQueriesHaveNoResults() {
        XCTAssertTrue(GlobalSearchIndex.search(" \n", entries: GlobalSearchIndex.settings).isEmpty)
    }

    func testTitleMatchesRankBeforeMentionsInSubtitles() {
        let entries = [
            GlobalSearchEntry(id: "a", kind: .book, title: "另一本书", subtitle: "作者谈森林", target: "a"),
            GlobalSearchEntry(id: "b", kind: .book, title: "森林来信", subtitle: "散文", target: "b")
        ]
        XCTAssertEqual(GlobalSearchIndex.search("森林", entries: entries).map(\.id), ["b", "a"])
    }

    func testMultipleTokensMatchAcrossTitleAndAuthorWithoutCaseOrWidthDifferences() {
        let entries = [GlobalSearchEntry(id: "b", kind: .book, title: "ABC 来信", subtitle: "José", target: "b")]
        XCTAssertEqual(GlobalSearchIndex.search("ａｂｃ JOSE", entries: entries).count, 1)
        XCTAssertTrue(GlobalSearchIndex.search("ABC 不存在", entries: entries).isEmpty)
    }

    func testResultsAreBoundedAndOrderIsStable() {
        let entries = (0..<140).map {
            GlobalSearchEntry(id: String(format: "%03d", $0), kind: .source,
                              title: "书源", subtitle: "", target: "source-\($0)")
        }
        let matches = GlobalSearchIndex.search("书源", entries: Array(entries.reversed()))
        XCTAssertEqual(matches.count, 100)
        XCTAssertEqual(matches.first?.id, "000")
        XCTAssertTrue(GlobalSearchIndex.search("书源", entries: entries, limit: 0).isEmpty)
    }

    func testSourceScopeOnlyReturnsEntriesOwnedByTheChosenSource() {
        let entries = [
            GlobalSearchEntry(id: "a", kind: .book, title: "同名作品", subtitle: "作者",
                              target: "a", sourceURL: "https://source-a.invalid"),
            GlobalSearchEntry(id: "b", kind: .book, title: "同名作品", subtitle: "作者",
                              target: "b", sourceURL: "https://source-b.invalid")
        ]
        let index = GlobalSearchIndex(entries: entries)
        XCTAssertEqual(index.search("同名", scope: .source, sourceURL: "https://source-a.invalid").map(\.id), ["a"])
        XCTAssertEqual(index.search("", scope: .source, sourceURL: "https://source-b.invalid").map(\.id), ["b"])
        XCTAssertTrue(index.search("同名", scope: .source).isEmpty,
                      "Source scope without a concrete source must not degrade to a subtitle search")
        XCTAssertTrue(index.search("同名", scope: .source, sourceURL: "https://missing.invalid").isEmpty)
    }

    func testSourceScopeIgnoresEntriesWhoseSubtitleMentionsTheSourceName() {
        let entries = [
            GlobalSearchEntry(id: "book", kind: .book, title: "书", subtitle: "聚合源 · 作者", target: "book",
                              sourceURL: "https://other.invalid"),
            GlobalSearchEntry(id: "source", kind: .source, title: "聚合源", subtitle: "书源",
                              target: "聚合源", sourceURL: "https://aggregate.invalid")
        ]
        let matches = GlobalSearchIndex(entries: entries)
            .search("聚合", scope: .source, sourceURL: "https://aggregate.invalid")
        XCTAssertEqual(matches.map(\.id), ["source"])
    }

    func testAuthorScopeOnlyMatchesTheAuthorField() {
        let entries = [
            GlobalSearchEntry(id: "a", kind: .book, title: "书", subtitle: "作者甲 · 简介里出现关键词",
                              target: "a", sourceURL: "source", author: "作者甲"),
            GlobalSearchEntry(id: "b", kind: .book, title: "书二", subtitle: "作者乙",
                              target: "b", sourceURL: "source", author: "作者乙")
        ]
        let index = GlobalSearchIndex(entries: entries)
        XCTAssertEqual(index.search("作者甲", scope: .author).map(\.id), ["a"])
        XCTAssertTrue(index.search("关键词", scope: .author).isEmpty,
                      "Author scope must not match the synopsis carried by subtitle")
    }

    func testBookmarkSearchRetainsTheOwningBookAndExactBookmark() {
        var book = BookshelfBook(searchBook: SearchBook(name: "原书", author: "作者", coverUrl: nil,
            bookUrl: "https://fixture.invalid/book", sourceName: "测试源", sourceUrl: "https://fixture.invalid"))
        let bookmark = ReaderBookmark(chapterIndex: 3, chapterTitle: "第四章", snippet: "树叶中的光")
        book.bookmarks = [bookmark]
        let matches = GlobalSearchIndex.search("树叶", entries: GlobalSearchIndex.entries(books: [book], sources: []))
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.target, book.id)
        XCTAssertEqual(matches.first?.bookmarkID, bookmark.id)
    }
}
