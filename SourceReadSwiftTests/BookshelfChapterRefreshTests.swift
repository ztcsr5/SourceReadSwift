import XCTest
@testable import SourceReadSwift

@MainActor
final class BookshelfChapterRefreshTests: XCTestCase {
    func testLaunchRunsOnceAndPullAddsAnUpdateUntilTheLatestChapterIsRead() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceStore = SourceStore(persistence: SourcePersistence(rootURL: directory))
        let shelf = BookshelfStore(persistence: BookshelfPersistence(rootURL: directory),
                                  groupPersistence: BookshelfGroupPersistence(rootURL: directory))
        let source = BookSource(bookSourceName: "Fixture", bookSourceUrl: "https://shelf.invalid")
        try sourceStore.importSources([source])
        let book = SearchBook(name: "更新测试", author: nil, coverUrl: nil, bookUrl: "https://shelf.invalid/book",
                              sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl)
        shelf.addOrUpdate(book)
        shelf.addLocalTextBook(OnboardingClassicBook.makeWelcomeBook())

        let engine = ShelfRefreshFixture()
        let refresh = BookshelfChapterRefreshCoordinator(shelf: shelf, sources: sourceStore, engine: engine)
        await refresh.refreshOnLaunch()
        XCTAssertEqual(shelf.book(id: book.id)?.totalChapters, 2)
        XCTAssertEqual(shelf.book(id: book.id)?.hasUpdates, false, "The first observed directory is a baseline")
        await engine.setChapterCount(3)
        await refresh.refreshOnLaunch()
        XCTAssertEqual(shelf.book(id: book.id)?.totalChapters, 2)

        let report = await refresh.refresh()
        XCTAssertEqual(report, .init(attempted: 1, checked: 1))
        XCTAssertEqual(shelf.book(id: book.id)?.hasUpdates, true)
        XCTAssertEqual(shelf.book(id: book.id)?.latestChapterTitle, "Chapter 3")
        shelf.markReaderOpened(bookID: book.id)
        XCTAssertEqual(shelf.book(id: book.id)?.hasUpdates, true)
        shelf.updateReadingProgress(bookID: book.id, chapterIndex: 2, chapterTitle: "Chapter 3", totalChapters: 3)
        XCTAssertEqual(shelf.book(id: book.id)?.hasUpdates, false)
    }

    func testLateRefreshCannotOverwriteAChangedSourceOrShorterDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let shelf = BookshelfStore(persistence: BookshelfPersistence(rootURL: directory),
                                  groupPersistence: BookshelfGroupPersistence(rootURL: directory))
        let first = SearchBook(name: "Fixture", author: nil, coverUrl: nil, bookUrl: "https://first.invalid/book",
                               sourceName: "First", sourceUrl: "https://first.invalid")
        let replacement = SearchBook(name: "Fixture", author: nil, coverUrl: nil, bookUrl: "https://other.invalid/book",
                                     sourceName: "Other", sourceUrl: "https://other.invalid")
        shelf.addOrUpdate(first)
        shelf.switchSource(bookID: first.id, to: replacement, latestChapterTitle: "Latest", intro: nil, totalChapters: 9)
        shelf.applyChapterRefresh([
            .init(shelfID: first.id, book: replacement, details: .init(latestChapterTitle: "Short prefix", intro: nil,
                                                                      totalChapters: 6, coverURL: nil, mediaKind: nil))
        ])
        shelf.applyChapterRefresh([
            .init(shelfID: first.id, book: first, details: .init(latestChapterTitle: "Stale update", intro: nil,
                                                               totalChapters: 15, coverURL: nil, mediaKind: nil))
        ])
        let saved = try XCTUnwrap(shelf.book(id: first.id))
        XCTAssertEqual(saved.latestChapterTitle, "Latest")
        XCTAssertEqual(saved.totalChapters, 9)
        XCTAssertEqual(saved.sourceURL, replacement.sourceUrl)
        XCTAssertFalse(saved.hasUpdates)
    }
}

private actor ShelfRefreshFixture: SourceEngine {
    private var chapterCount = 2

    func setChapterCount(_ count: Int) { chapterCount = count }

    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> {
        .success([])
    }

    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> {
        .success(.init(name: book.name, author: book.author, coverUrl: nil, bookUrl: book.bookUrl,
                       sourceName: book.sourceName, sourceUrl: book.sourceUrl, intro: nil, latestChapter: nil))
    }

    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> {
        .success((0..<chapterCount).map { index in
            .init(title: "Chapter \(index + 1)", url: book.bookUrl + "/\(index)", bookUrl: book.bookUrl, index: index)
        })
    }

    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        .failure(.unsupported("Refresh fixture"))
    }

    func verifyLogin(source: BookSource) async -> Result<SourceLoginVerification, SourceEngineError> {
        .failure(.unsupported("Refresh fixture"))
    }
}
