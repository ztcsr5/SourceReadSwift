import XCTest
@testable import SourceReadSwift

@MainActor
final class ComicReadingPositionTests: XCTestCase {
    private let source = "https://comic-position.invalid"
    private var chapter: BookChapter {
        BookChapter(title: "Chapter", url: source + "/chapter/7", bookUrl: source + "/book", index: 7)
    }
    private var pages: [ComicPage] {
        (0..<4).map { ComicPage(id: $0, url: source + "/\($0).png?token=private-fixture") }
    }

    func testPositionFollowsTheSameImageAfterPagesAreInserted() throws {
        let saved = ComicReadingPosition(sourceURL: source, chapter: chapter, pages: pages,
                                         anchor: ComicPageAnchor(pageIndex: 2, fraction: 0.625))
        let shifted = [ComicPage(id: 99, url: source + "/inserted.png")] + pages
        let restored = try XCTUnwrap(saved.resolve(sourceURL: source, chapter: chapter, pages: shifted))
        XCTAssertEqual(restored.pageIndex, 3)
        XCTAssertEqual(restored.fraction, 0.625)
        XCTAssertNil(saved.resolve(sourceURL: source + "/other", chapter: chapter, pages: pages))
    }

    func testChangedImageCountFallsBackToAClampedPageWithoutInventingPrecision() throws {
        let saved = ComicReadingPosition(sourceURL: source, chapter: chapter, pages: pages,
                                         anchor: ComicPageAnchor(pageIndex: 3, fraction: 0.8))
        let replaced = [ComicPage(id: 0, url: source + "/replacement.png")]
        let restored = try XCTUnwrap(saved.resolve(sourceURL: source, chapter: chapter, pages: replaced))
        XCTAssertEqual(restored, ComicPageAnchor(pageIndex: 0, fraction: 0))
        XCTAssertNil(saved.resolve(sourceURL: source, chapter: chapter, pages: []))
        XCTAssertEqual(ComicPageAnchor(pageIndex: -1, fraction: .nan), ComicPageAnchor(pageIndex: 0, fraction: 0))
    }

    func testCursorSurvivesRealShelfWritesAndContainsNoImageAddressOrHeaders() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = BookshelfPersistence(fileManager: .default, rootURL: root)
        let shelf = BookshelfStore(persistence: persistence)
        let search = SearchBook(name: "Comic", author: nil, coverUrl: nil, bookUrl: source + "/book", sourceName: "Fixture", sourceUrl: source)
        shelf.addOrUpdate(search)
        let saved = ComicReadingPosition(sourceURL: source, chapter: chapter, pages: pages,
                                         anchor: ComicPageAnchor(pageIndex: 2, fraction: 0.625))
        shelf.updateReadingProgress(bookID: search.id, chapterIndex: 7, chapterTitle: "Chapter",
                                    totalChapters: 10, paragraphIndex: 2, comicPosition: saved)
        await shelf.waitForPendingWrites()
        let restored = BookshelfStore(persistence: persistence).book(id: search.id)
        XCTAssertEqual(restored?.comicPosition, saved)
        XCTAssertEqual(restored?.currentParagraphIndex, 2)
        let bytes = try JSONEncoder().encode(saved)
        let json = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        XCTAssertFalse(json.contains("private-fixture"))
        XCTAssertFalse(json.contains(".png"))
        XCTAssertFalse(json.contains("https://"))
        shelf.switchSource(bookID: search.id, to: search, latestChapterTitle: nil, intro: nil, totalChapters: 10)
        XCTAssertNil(shelf.book(id: search.id)?.comicPosition)
    }

    func testLegacyShelfWithoutComicCursorStillDecodes() throws {
        let book = BookshelfBook(searchBook: SearchBook(name: "Legacy", author: nil, coverUrl: nil, bookUrl: source + "/book",
                                                       sourceName: "Fixture", sourceUrl: source))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(book)) as? [String: Any])
        object.removeValue(forKey: "comicPosition")
        let decoded = try JSONDecoder().decode(BookshelfBook.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.comicPosition)
    }

    func testSignedAddressesCanBecomeOfflineFilesWithoutLosingTheReadingLine() throws {
        let saved = ComicReadingPosition(sourceURL: source, chapter: chapter, pages: pages,
                                         anchor: ComicPageAnchor(pageIndex: 2, fraction: 0.625))
        let offline = BookChapter(title: chapter.title, url: "srcomic://chapter/" + saved.chapterKey,
                                  bookUrl: chapter.bookUrl, index: chapter.index)
        let files = pages.indices.map { ComicPage(id: $0, url: "file:///offline/page-\($0).img") }
        let restored = try XCTUnwrap(saved.resolve(sourceURL: source, chapter: offline, pages: files))
        XCTAssertEqual(restored, ComicPageAnchor(pageIndex: 2, fraction: 0.625))
    }
}
