import XCTest
@testable import SourceReadSwift

final class SearchURLResolverTests: XCTestCase {
    func testResolveTemplateSearchUrl() throws {
        let source = BookSource(
            bookSourceName: "测试源",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/search?q={{keyword}}&page={{page}}"
        )

        let result = SearchURLResolver().resolve(source: source, keyword: "斗破苍穹", page: 3)
        guard case .success(let url) = result else {
            return XCTFail("expected success")
        }
        XCTAssertTrue(url.contains("page=3"))
    }

    func testResolveSingleBraceKeywordAndPageArithmetic() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/search?q={key}&offset={{(page - 1) * 10}}"
        )

        let result = SearchURLResolver().resolve(source: source, keyword: "abc def", page: 3)

        guard case .success(let url) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(url, "https://example.com/search?q=abc%20def&offset=20")
    }

    func testResolveJavaScriptSearchUrl() throws {
        let source = BookSource(
            bookSourceName: "测试源",
            bookSourceUrl: "https://example.com",
            searchUrl: "@js:'https://example.com/search?q=' + java.urlEncode(keyword)"
        )

        let result = SearchURLResolver().resolve(source: source, keyword: "斗破苍穹", page: 1)
        guard case .success(let url) = result else {
            return XCTFail("expected success")
        }
        XCTAssertTrue(url.hasPrefix("https://example.com/search?q="))
    }

    func testResolveJavaScriptSearchUrlWithTopLevelReturn() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            searchUrl: "@js:return 'https://example.com/search?q=' + java.urlEncode(keyword)"
        )

        let result = SearchURLResolver().resolve(source: source, keyword: "\u{6597}\u{7834}\u{82cd}\u{7a79}", page: 1)
        guard case .success(let url) = result else {
            return XCTFail("expected success")
        }
        XCTAssertTrue(url.hasPrefix("https://example.com/search?q="))
    }

    func testResolveEmbeddedJavaScriptSegment() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/search?q=<js>java.urlEncode(keyword)</js>&page={{page}}"
        )

        let result = SearchURLResolver().resolve(source: source, keyword: "abc def", page: 2)
        guard case .success(let url) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(url, "https://example.com/search?q=abc%20def&page=2")
    }

    func testResolveSourceTemplateVariables() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            searchUrl: "{{source.api}}/{{source.path}}?q={{keyword}}&base={{source.bookSourceUrl}}",
            raw: [
                "api": "https://api.example.com",
                "path": "search"
            ]
        )

        let result = SearchURLResolver().resolve(source: source, keyword: "abc", page: 1)

        guard case .success(let url) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(url, "https://api.example.com/search?q=abc&base=https://example.com")
    }

    func testResolveJavaScriptCanReadSourceObject() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            searchUrl: "@js:source.bookSourceUrl + '/search?q=' + java.urlEncode(key)"
        )

        let result = SearchURLResolver().resolve(source: source, keyword: "abc def", page: 1)

        guard case .success(let url) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(url, "https://example.com/search?q=abc%20def")
    }

    func testResolveStripsCookieMacrosBeforeRelativeResolution() throws {
        let source = BookSource(
            bookSourceName: "小原文学网",
            bookSourceUrl: "https://www.min-yuan.com",
            searchUrl: "{{cookie.removeCookie(source.key)}}\n/search/,{\n  \"body\": \"searchkey={{key}}\",\n  \"method\": \"POST\"\n}"
        )

        let result = SearchURLResolver().resolve(source: source, keyword: "剑来", page: 1)

        guard case .success(let url) = result else {
            return XCTFail("expected success")
        }
        XCTAssertTrue(url.hasPrefix("/search/,"))
        XCTAssertFalse(url.contains("cookie.removeCookie"))

        let request = SourceRequestBuilder().buildPageRequest(source: source, urlText: url)
        XCTAssertEqual(request.url.absoluteString, "https://www.min-yuan.com/search/")
    }

    func testResolveInlineScriptSideEffectsAndTrim() throws {
        let source = BookSource(
            bookSourceName: "搬文屋",
            bookSourceUrl: "https://www.banwenwu.com",
            searchUrl: "{{url=source.getKey();cookie.removeCookie(url)}}\n/modules/article/search.php?searchkey={{key}}"
        )

        let result = SearchURLResolver().resolve(source: source, keyword: "宿命之环", page: 1)
        guard case .success(let url) = result else {
            return XCTFail("expected success")
        }
        XCTAssertFalse(url.contains("cookie.removeCookie"))
        XCTAssertFalse(url.contains("source.getKey"))
        XCTAssertTrue(url.hasPrefix("/modules/article/search.php?searchkey="))

        let request = SourceRequestBuilder().buildPageRequest(source: source, urlText: url)
        XCTAssertEqual(request.url.path, "/modules/article/search.php")
    }

    func testResolveBaseUrlWithFragment() throws {
        let source = BookSource(
            bookSourceName: "快眼看书",
            bookSourceUrl: "http://www.kyxsw.org#🎃",
            searchUrl: "{{baseUrl}}/search.html?keyword={{key}}"
        )

        let result = SearchURLResolver().resolve(source: source, keyword: "凡人", page: 1)
        guard case .success(let url) = result else {
            return XCTFail("expected success")
        }
        XCTAssertFalse(url.contains("#"))
        XCTAssertTrue(url.hasPrefix("http://www.kyxsw.org/search.html?keyword="))
    }

    func testResolveSourceUrlWithFragmentPlaceholder() throws {
        let source = BookSource(
            bookSourceName: "无限小说",
            bookSourceUrl: "http://m.wenxuesk.info#🎃",
            searchUrl: "{{sourceUrl}}/modules/article/search.php?searchkey={{key}}"
        )

        XCTAssertEqual(source.cleanSourceURL, "http://m.wenxuesk.info")

        let result = SearchURLResolver().resolve(source: source, keyword: "重生", page: 1)
        guard case .success(let url) = result else {
            return XCTFail("expected success")
        }
        XCTAssertFalse(url.contains("#"))
        XCTAssertEqual(url, "http://m.wenxuesk.info/modules/article/search.php?searchkey=%E9%87%8D%E7%94%9F")
    }

    func testBuildRequestFixesFragmentPathConcatenation() throws {
        let source = BookSource(
            bookSourceName: "棉花糖",
            bookSourceUrl: "https://www.mhtxs.la#🎃",
            searchUrl: "https://www.mhtxs.la#🎃/search.php?keyword={{key}}"
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "重生",
            page: 1
        )
        XCTAssertEqual(request.url.scheme, "https")
        XCTAssertEqual(request.url.host, "www.mhtxs.la")
        XCTAssertEqual(request.url.path, "/search.php")
        XCTAssertFalse(request.url.absoluteString.contains("#"))
    }

    func testAppVersionSemantics() {
        XCTAssertEqual(AppVersion.versionString, "1.0.0")
        XCTAssertEqual(AppVersion.epic, 1)
        XCTAssertEqual(AppVersion.major, 0)
        XCTAssertEqual(AppVersion.minor, 0)
        XCTAssertTrue(AppVersion.displayString.contains("1.0.0"))
    }
}
