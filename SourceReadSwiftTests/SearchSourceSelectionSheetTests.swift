import XCTest
@testable import SourceReadSwift

@MainActor
final class SearchSourceSelectionSheetTests: XCTestCase {
    private let sources = [
        BookSource(bookSourceName: "WEBTOON 漫画", bookSourceUrl: "https://webtoons.example"),
        BookSource(bookSourceName: "森林书屋", bookSourceUrl: "https://forest.example")
    ]

    func testWhitespaceQueryPreservesSourceOrder() {
        XCTAssertEqual(SearchSourceSelectionSheet.matchingSources(sources, query: " \n ").map(\.id), sources.map(\.id))
    }

    func testNameAndURLAreBothSearchableIgnoringCaseAndOuterWhitespace() {
        XCTAssertEqual(SearchSourceSelectionSheet.matchingSources(sources, query: " webtoon ").map(\.id), [sources[0].id])
        XCTAssertEqual(SearchSourceSelectionSheet.matchingSources(sources, query: "FOREST.EXAMPLE").map(\.id), [sources[1].id])
        XCTAssertEqual(SearchSourceSelectionSheet.matchingSources(sources, query: "森林").map(\.id), [sources[1].id])
    }

    func testNoMatchAndEmptySourceCollectionRemainEmpty() {
        XCTAssertTrue(SearchSourceSelectionSheet.matchingSources(sources, query: "not present").isEmpty)
        XCTAssertTrue(SearchSourceSelectionSheet.matchingSources([], query: "webtoon").isEmpty)
    }
}
