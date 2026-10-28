import XCTest
@testable import SourceReadSwift

/// Regressions for the Legado URL-resolution gaps that broke the private bank
/// audit: bare-path `searchUrl`, relative `tocUrl`, and `{{source}}` leaking a
/// Swift struct dump into a request parameter.
final class SourceURLResolutionTests: XCTestCase {

    func testSearchURLResolverJoinsBarePathWithBookSourceURL() {
        let source = BookSource(
            bookSourceName: "爱丽丝书屋",
            bookSourceUrl: "https://www.alice.com",
            searchUrl: "/search.html?q={{key}}"
        )

        let result = SearchURLResolver().resolve(source: source, keyword: "斗破苍穹", page: 1)

        guard case .success(let url) = result else {
            return XCTFail("expected resolved URL, got \(result)")
        }
        XCTAssertTrue(url.hasPrefix("https://www.alice.com/search.html?q="), "unexpected URL: \(url)")
        XCTAssertFalse(url.hasPrefix("/search.html"), "bare path was not absolutized: \(url)")
    }

    func testDynamicURLResolverAbsolutizesRelativeTOCURL() {
        let source = BookSource(bookSourceName: "相对目录", bookSourceUrl: "https://www.alice.com")
        let resolved = DynamicURLResolver.resolve(
            "/api/chapter?bookId=1",
            baseUrl: "https://www.alice.com/book/1",
            source: source,
            context: RuleExecutionContext()
        )

        XCTAssertEqual(resolved, "https://www.alice.com/api/chapter?bookId=1")
    }

    func testDynamicURLResolverKeepsPOSTDirectiveSuffix() {
        let source = BookSource(bookSourceName: "相对目录", bookSourceUrl: "https://www.alice.com")
        let resolved = DynamicURLResolver.resolve(
            "/api/search,{\"method\":\"POST\"}",
            baseUrl: "https://www.alice.com/",
            source: source,
            context: RuleExecutionContext()
        )

        XCTAssertEqual(resolved, "https://www.alice.com/api/search,{\"method\":\"POST\"}")
    }

    func testSourcePlaceholderExpandsToBookSourceURL() {
        let source = BookSource(bookSourceName: "STV", bookSourceUrl: "https://sangtacviet.com")
        let value = JSONRuleExtractor().string(
            from: ["id": "1"],
            rule: "@js:'https://sangtacviet.com/index.php?h={{source}}'",
            fallbackKeys: [],
            variables: ["source": source]
        )

        XCTAssertEqual(value, "https://sangtacviet.com/index.php?h=https://sangtacviet.com")
        XCTAssertFalse(value?.contains("BookSource(") ?? true, "struct dump leaked: \(value ?? "nil")")
    }
}
