import XCTest
@testable import SourceReadSwift

@MainActor
final class DiscoverViewModelTests: XCTestCase {
    func testClearSearchCancelsAndResetsAllVisibleState() {
        let viewModel = DiscoverViewModel()
        viewModel.keyword = "三体"
        viewModel.results = [
            SearchBook(
                name: "三体",
                author: "刘慈欣",
                coverUrl: nil,
                bookUrl: "https://fixture.invalid/book/1",
                sourceName: "Fixture",
                sourceUrl: "https://fixture.invalid",
                intro: nil
            )
        ]
        viewModel.errorMessage = "fixture error"
        viewModel.checkedSourceCount = 3
        viewModel.hitSourceCount = 1
        viewModel.totalResultCount = 1
        viewModel.resultFilter = "Fixture"

        viewModel.clearSearch()

        XCTAssertEqual(viewModel.keyword, "")
        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertFalse(viewModel.hasSearchState)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.checkedSourceCount, 0)
        XCTAssertEqual(viewModel.hitSourceCount, 0)
        XCTAssertEqual(viewModel.totalResultCount, 0)
        XCTAssertEqual(viewModel.resultFilter, "")
    }

    func testClearSearchIsSafeWhenNoSearchHasStarted() {
        let viewModel = DiscoverViewModel()

        viewModel.clearSearch()

        XCTAssertEqual(viewModel.keyword, "")
        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertFalse(viewModel.isSearching)
        XCTAssertFalse(viewModel.hasSearchState)
    }

    func testSearchSourceScopeFiltersTheLocalProjection() {
        let first = SearchBook(name: "同名作品", author: "作者", coverUrl: nil,
            bookUrl: "https://a.invalid/book", sourceName: "A", sourceUrl: "https://a.invalid")
        let second = SearchBook(name: "同名作品", author: "作者", coverUrl: nil,
            bookUrl: "https://b.invalid/book", sourceName: "B", sourceUrl: "https://b.invalid")
        let projection = DiscoverViewModel.makeProjection([first, second], kinds: [:], kind: nil,
            sourceURL: "https://a.invalid", query: "", scope: .all)
        XCTAssertEqual(projection.results.map(\.id), [first.id])
        XCTAssertEqual(projection.aggregated.count, 1)
    }

    func testSetAndClearSearchSourceAreIdempotent() {
        let viewModel = DiscoverViewModel()
        viewModel.setSearchSource(url: " https://a.invalid ")
        XCTAssertEqual(viewModel.selectedSourceURL, "https://a.invalid")
        viewModel.setSearchSource(url: "https://a.invalid")
        XCTAssertEqual(viewModel.selectedSourceURL, "https://a.invalid")
        viewModel.clearSearchSource()
        XCTAssertNil(viewModel.selectedSourceURL)
        XCTAssertNil(viewModel.selectedSourceName)
    }

    func testSelectSourceKindUpdatesFilter() {
        let viewModel = DiscoverViewModel()
        XCTAssertNil(viewModel.selectedSourceKind)

        viewModel.selectSourceKind(.audio)
        XCTAssertEqual(viewModel.selectedSourceKind, .audio)

        viewModel.selectSourceKind(nil)
        XCTAssertNil(viewModel.selectedSourceKind)
    }

    func testLargeSourceSweepVisitsEveryEligibleSourceAndReportsTheInventory() async throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: location) }
        let sources = SourceStore(persistence: SourcePersistence(rootURL: location))
        let shelf = BookshelfStore(persistence: BookshelfPersistence(rootURL: location),
                                   groupPersistence: BookshelfGroupPersistence(rootURL: location))
        let imported = (0..<997).map { index in
            BookSource(bookSourceName: "Audio fixture \(index)", bookSourceUrl: "https://fixture-\(index).invalid",
                       bookSourceType: 1, enabled: index != 0, searchUrl: (1...3).contains(index) ? nil : "/search")
        }
        try sources.importSources(imported)
        shelf.addOrUpdate(SearchBook(name: "Fixture", author: nil, coverUrl: nil,
            bookUrl: "https://fixture-4.invalid/audio", sourceName: "Fixture", sourceUrl: "https://fixture-4.invalid"))
        let engine = SourceSweepFixture()
        let state = AppState(sourceStore: sources, bookshelfStore: shelf, engine: engine)
        let discover = state.discoverViewModel
        discover.selectSourceKind(.audio)
        discover.keyword = "Sweep Sample"
        await discover.search(generation: 0)
        XCTAssertEqual(discover.sourceCoverage, .init(importedCount: 997, enabledCount: 996,
                                                      searchableCount: 993, targetCount: 993))
        XCTAssertEqual(discover.checkedSourceCount, 993)
        XCTAssertEqual(discover.hitSourceCount, 1)
        XCTAssertEqual(discover.failedSourceCount, 0)
        XCTAssertEqual(discover.results.map(\.sourceUrl), ["https://fixture-996.invalid"])
        let requests = await engine.requests
        XCTAssertEqual(requests.count, 993)
        XCTAssertEqual(Set(requests).count, requests.count)
        XCTAssertTrue(discover.hasFinishedSearch)
    }
}

private actor SourceSweepFixture: SourceEngine {
    private(set) var requests: [String] = []

    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> {
        requests.append(source.bookSourceUrl)
        guard source.bookSourceUrl == "https://fixture-996.invalid" else { return .success([]) }
        return .success([SearchBook(name: keyword, author: "Fixture", coverUrl: nil,
            bookUrl: source.bookSourceUrl + "/audio", sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl)])
    }

    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> {
        .failure(.unsupported("Search fixture"))
    }

    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> {
        .failure(.unsupported("Search fixture"))
    }

    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        .failure(.unsupported("Search fixture"))
    }

    func verifyLogin(source: BookSource) async -> Result<SourceLoginVerification, SourceEngineError> {
        .failure(.unsupported("Search fixture"))
    }
}
