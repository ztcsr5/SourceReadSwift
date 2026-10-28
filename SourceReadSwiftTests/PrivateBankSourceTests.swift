import XCTest
@testable import SourceReadSwift

/// End-to-end regression for the user-supplied “番茄小说TS” Legado source
/// (`shareBookSource (2).json`).  The fixture stores the source verbatim plus
/// one real `/search?tab_type=3` response captured on 2026-10-28, so the test
/// exercises the whole chain: BookSource decode → jsLib preload → `@js:`
/// searchUrl → `@js:` bookList → SearchBook projection.
final class PrivateBankSourceTests: XCTestCase {
    private func tomatoSource() throws -> BookSource {
        let url = TestFixtureSupport.directory("private-bank")
            .appendingPathComponent("tomato-source.json")
        let data = try Data(contentsOf: url)
        let sources = try JSONDecoder().decode([BookSource].self, from: data)
        XCTAssertEqual(sources.count, 1)
        return try XCTUnwrap(sources.first)
    }

    func testTomatoSourceCarriesJSLibraryAndSearchRules() throws {
        let source = try tomatoSource()
        XCTAssertEqual(source.bookSourceUrl, "https://fq.tangsongxs.com")
        XCTAssertTrue(source.bookSourceName.contains("番茄"), source.bookSourceName)
        XCTAssertTrue(try XCTUnwrap(source.searchUrl).hasPrefix("@js:"))
        XCTAssertFalse(try XCTUnwrap(source.raw["jsLib"]).isEmpty)
        XCTAssertFalse(try XCTUnwrap(source.exploreUrl).isEmpty)
        XCTAssertNotNil(source.ruleSearch)
        XCTAssertTrue(try XCTUnwrap(source.ruleSearch?.fields["bookList"]).contains("@js:"))
    }

    func testTomatoSearchURLResolvesToNovelTab() throws {
        let source = try tomatoSource()
        let result = SearchURLResolver().resolve(
            source: source,
            keyword: "系统",
            page: 1,
            executionContext: RuleExecutionContext(source: source)
        )
        guard case .success(let url) = result else {
            return XCTFail("searchUrl @js failed to resolve: \(result)")
        }
        XCTAssertTrue(url.hasPrefix("https://fq.tangsongxs.com/search?"), url)
        XCTAssertTrue(url.contains("tab_type=3"), url)
        XCTAssertTrue(url.contains("offset=0"), url)
    }

    func testTomatoSearchFixtureReturnsNovelBooks() throws {
        let source = try tomatoSource()
        let bodyURL = TestFixtureSupport.directory("private-bank")
            .appendingPathComponent("tomato-search.json")
        let body = String(decoding: try Data(contentsOf: bodyURL), as: UTF8.self)
        let response = SourceResponse(
            url: URL(string: "https://fq.tangsongxs.com/search?query=%E7%B3%BB%E7%BB%9F&offset=0&tab_type=3")!,
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: body,
            data: Data()
        )
        let result = SearchResultParser(executionContext: RuleExecutionContext(source: source))
            .parse(source: source, response: response, keyword: "系统")
        guard case .success(let books) = result else {
            return XCTFail("tomato search fixture failed: \(result)")
        }
        XCTAssertGreaterThanOrEqual(books.count, 1)
        let first = try XCTUnwrap(books.first)
        XCTAssertFalse(first.name.isEmpty)
        XCTAssertTrue(first.bookUrl.contains("/detail?book_id="), first.bookUrl)
        XCTAssertEqual(first.sourceName, source.bookSourceName)
        XCTAssertEqual(first.sourceUrl, source.bookSourceUrl)
    }
}
