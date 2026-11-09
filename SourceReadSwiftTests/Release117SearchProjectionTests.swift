import XCTest
@testable import SourceReadSwift

final class Release117SearchProjectionTests: XCTestCase {
    func testShelfMembershipIgnoresProgressButTracksInsertionRemovalAndLocalAliases() {
        let remote = book(1)
        var saved = BookshelfBook(searchBook: remote)
        let original = DiscoverView.BookshelfMembership(books: [saved])
        saved.currentChapterIndex = 7
        saved.currentParagraphIndex = 42
        saved.lastReadAt = Date()
        XCTAssertEqual(DiscoverView.BookshelfMembership(books: [saved]), original,
                       "Reading progress must not invalidate an offscreen results list")
        XCTAssertTrue(original.contains(remote))
        XCTAssertFalse(DiscoverView.BookshelfMembership(books: []).contains(remote))
        XCTAssertFalse(original.contains(book(2)))
        let localAlias = SearchBook(name: remote.name, author: remote.author, coverUrl: nil,
                                   bookUrl: remote.bookUrl, sourceName: "Local", sourceUrl: "local://text")
        XCTAssertTrue(original.contains(localAlias))
        XCTAssertNotEqual(DiscoverView.BookshelfMembership(books: [saved, BookshelfBook(searchBook: book(2))]), original)
    }

    func testLargeDuplicateGroupKeepsStableOrderWithoutQuadraticMembershipScans() async {
        let books = (0..<10_000).map { book($0) }
        let start = Date()
        let projection = await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            return DiscoverViewModel.makeProjection(books + books, kinds: [:], kind: nil, query: "", scope: .all)
        }.value
        XCTAssertEqual(projection.results.count, 20_000)
        XCTAssertEqual(projection.aggregated.count, 1)
        XCTAssertEqual(projection.aggregated.first?.sources.count, 10_000)
        XCTAssertEqual(projection.aggregated.first?.sources.first?.bookUrl, books.first?.bookUrl)
        XCTAssertEqual(projection.aggregated.first?.sources.last?.bookUrl, books.last?.bookUrl)
        print("SEARCH_PROJECTION 20000 rows / 10000 distinct sources: \(Date().timeIntervalSince(start)) seconds, off-main")
    }

    func testProjectionCombinesKindAndTextFilterBeforeGrouping() {
        let text = book(1)
        let comic = SearchBook(name: "漫画", author: "作者", coverUrl: nil, bookUrl: "https://comic.example/1",
                               sourceName: "Comic", sourceUrl: "https://comic.example", intro: nil)
        let projection = DiscoverViewModel.makeProjection([text, comic], kinds: [comic.sourceUrl: .comic],
                                                          kind: .comic, query: "漫画", scope: .all)
        XCTAssertEqual(projection.results.map(\.bookUrl), [comic.bookUrl])
        XCTAssertEqual(projection.groups.count, 1)
        XCTAssertEqual(projection.aggregated.first?.name, "漫画")
    }

    @MainActor func testCancelledPublisherCannotInstallItsSnapshot() async {
        let model = DiscoverViewModel()
        let books = (0..<100).map { book($0) }
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await model.installRankedResults(books)
        }
        await task.value
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertTrue(model.aggregatedResults.isEmpty)
    }

    @MainActor func testInstalledProjectionKeepsTwentyRowPaginationAndClampsPageAfterFiltering() async {
        let model = DiscoverViewModel()
        let books = (0..<45).map { index in
            SearchBook(name: "书\(index)", author: "作者", coverUrl: nil, bookUrl: "https://source.example/\(index)",
                       sourceName: "Source", sourceUrl: "https://source.example", intro: nil)
        }
        await model.installRankedResults(books)
        XCTAssertEqual(model.pagedAggregatedResults.count, 20)
        model.resultPage = 2
        XCTAssertEqual(model.pagedAggregatedResults.count, 5)
        model.resultFilter = "书44"
        model.applyResultFilter()
        XCTAssertEqual(model.resultPage, 0)
        XCTAssertEqual(model.pagedAggregatedResults.count, 1)
    }

    private func book(_ index: Int) -> SearchBook {
        .init(name: "同一本书", author: "作者", coverUrl: nil, bookUrl: "https://source.example/book/\(index)",
              sourceName: "Source", sourceUrl: "https://source.example/\(index)", intro: nil)
    }
}
