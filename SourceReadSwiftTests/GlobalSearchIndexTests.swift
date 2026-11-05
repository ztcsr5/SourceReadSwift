import XCTest
@testable import SourceReadSwift

final class GlobalSearchIndexTests: XCTestCase {
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
