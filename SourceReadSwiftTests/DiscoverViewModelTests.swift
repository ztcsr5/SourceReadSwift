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
}
