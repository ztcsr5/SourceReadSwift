import XCTest
import SwiftSoup
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

        XCTAssertEqual(source.cleanSourceURL, "http://m.wenxuesk.info/")

        let result = SearchURLResolver().resolve(source: source, keyword: "重生", page: 1)
        guard case .success(let url) = result else {
            return XCTFail("expected success")
        }
        XCTAssertFalse(url.contains("#"))
        XCTAssertEqual(url, "http://m.wenxuesk.info/modules/article/search.php?searchkey=%E9%87%8D%E7%94%9F")
    }

    func testResolveBaseUrlWithoutLeadingSlash() throws {
        let source = BookSource(
            bookSourceName: "八一中文",
            bookSourceUrl: "https://www.blxs.la",
            searchUrl: "{{baseUrl}}modules/article/search.php?searchkey={{key}}"
        )

        XCTAssertEqual(source.cleanSourceURL, "https://www.blxs.la/")

        let result = SearchURLResolver().resolve(source: source, keyword: "重生", page: 1)
        guard case .success(let url) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(url, "https://www.blxs.la/modules/article/search.php?searchkey=%E9%87%8D%E7%94%9F")
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

    func testPreservesJSONOptionsAndHeaderDirectivesWithoutPercentEncodingBraces() throws {
        let postSource = BookSource(
            bookSourceName: "POST源",
            bookSourceUrl: "https://example.com",
            searchUrl: #"https://example.com/search,{"method":"POST","body":"key={{key}}&page={{page}}"}"#
        )
        let postResolved = try SearchURLResolver().resolve(source: postSource, keyword: "剑来", page: 1).get()
        XCTAssertFalse(postResolved.contains("%7B"))
        XCTAssertFalse(postResolved.contains("%22"))
        let postRequest = SourceRequestBuilder().buildSearchRequest(
            source: postSource,
            searchUrl: postResolved,
            keyword: "剑来",
            page: 1
        )
        XCTAssertEqual(postRequest.url.absoluteString, "https://example.com/search")
        XCTAssertEqual(postRequest.method, .post)
        XCTAssertEqual(postRequest.body.flatMap { String(data: $0, encoding: .utf8) }, "key=%E5%89%91%E6%9D%A5&page=1")

        let headerSource = BookSource(
            bookSourceName: "Header源",
            bookSourceUrl: "https://example.com",
            searchUrl: #"https://example.com/search?q={{key}}@Header:{"User-Agent":"CustomReader/1.0"}"#
        )
        let headerResolved = try SearchURLResolver().resolve(source: headerSource, keyword: "剑来", page: 1).get()
        XCTAssertFalse(headerResolved.contains("%7B"))
        XCTAssertFalse(headerResolved.contains("%22"))
        let headerRequest = SourceRequestBuilder().buildSearchRequest(
            source: headerSource,
            searchUrl: headerResolved,
            keyword: "剑来",
            page: 1
        )
        XCTAssertEqual(headerRequest.url.absoluteString, "https://example.com/search?q=%E5%89%91%E6%9D%A5")
        XCTAssertEqual(headerRequest.headers["User-Agent"], "CustomReader/1.0")
    }

    func testJSONPostSearchBodyReceivesRawUTF8Keyword() throws {
        let source = BookSource(
            bookSourceName: "JSON搜索源",
            bookSourceUrl: "https://example.com",
            searchUrl: #"https://example.com/api/search,{"method":"POST","body":"{\"searchTerms\":\"{{key}}\"}"}"#
        )
        let resolved = try SearchURLResolver().resolve(source: source, keyword: "剑来", page: 1).get()
        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: resolved,
            keyword: "剑来",
            page: 1
        )
        XCTAssertEqual(request.url.absoluteString, "https://example.com/api/search")
        XCTAssertEqual(request.method, .post)
        let bodyString = try XCTUnwrap(request.body.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertEqual(bodyString, #"{"searchTerms":"剑来"}"#)
        XCTAssertFalse(bodyString.contains("%E5%89%91%E6%9D%A5"))
    }

    func testAngleBracketPaginationInSearchUrl() throws {
        let source = BookSource(
            bookSourceName: "书法小说（优+）",
            bookSourceUrl: "https://www.shufaxiaoshuo.com",
            searchUrl: "https://www.shufaxiaoshuo.com/search/{{key}}<,&p={{page}}>"
        )

        let page1 = try SearchURLResolver().resolve(source: source, keyword: "剑来", page: 1).get()
        XCTAssertEqual(page1, "https://www.shufaxiaoshuo.com/search/%E5%89%91%E6%9D%A5")

        let page2 = try SearchURLResolver().resolve(source: source, keyword: "剑来", page: 2).get()
        XCTAssertEqual(page2, "https://www.shufaxiaoshuo.com/search/%E5%89%91%E6%9D%A5&p=2")
    }

    func testResolveURLPreservesExistingPercentEncodingWithoutDoubleEncoding() {
        let builder = SourceRequestBuilder()
        let raw = #"https://boxnovel.baidu.com/search?data={"word":"%E5%89%91%E6%9D%A5"}"#
        let url = builder.resolveURL(raw, relativeTo: "https://boxnovel.baidu.com")
        XCTAssertTrue(url.absoluteString.contains("%E5%89%91%E6%9D%A5"))
        XCTAssertFalse(url.absoluteString.contains("%25E5"))
        XCTAssertTrue(url.absoluteString.contains("%7B%22word%22:%22%E5%89%91%E6%9D%A5%22%7D"))
    }

    func testBaseUrlWithFragmentCommentAndRelativePathInsertsSlash() throws {
        let source = BookSource(
            bookSourceName: "八一中文",
            bookSourceUrl: "https://www.blxs.la#comment",
            searchUrl: "{{baseUrl}}modules/article/search.php"
        )
        let resolved = try SearchURLResolver().resolve(source: source, keyword: "剑来", page: 1).get()
        XCTAssertEqual(resolved, "https://www.blxs.la/modules/article/search.php")
    }

    func testJSCoreRuntimeJSONParseUnwrapsBridgeResponseFromJavaAjax() throws {
        let runtime = JSCoreRuntime(ajaxHandler: { _ in
            #"{"status":200,"bookName":"剑来"}"#
        })
        let parsedName = try runtime.evaluate(#"JSON.parse(java.ajax("https://example.com/api")).bookName"#).get()
        XCTAssertEqual(parsedName, "剑来")

        let getJsonName = try runtime.evaluate(#"java.getJson(java.ajax("https://example.com/api")).bookName"#).get()
        XCTAssertEqual(getJsonName, "剑来")
    }

    func testCompoundClassTagSelectorAndXPathPositionRangePredicates() throws {
        let steps = LegadoDefaultRuleTranslator.translateSelectorSteps("class.chapter.ul.1@li")
        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0].selector, ".chapter ul, .chapter.ul")
        XCTAssertEqual(steps[0].indices, [1])
        XCTAssertEqual(steps[1].selector, "li")

        let html = """
        <div class="chapter">
          <ul><li>最新章节1</li></ul>
          <ul><li>第一章</li><li>第二章</li></ul>
        </div>
        <div id="chapterlist">
          <p><a href="/header">Header</a></p>
          <p><a href="/1">Ch 1</a></p>
          <p><a href="/2">Ch 2</a></p>
          <p><a href="/footer">Footer</a></p>
        </div>
        """
        let doc = try SwiftSoup.parse(html)
        let liElements = LegadoDefaultRuleTranslator.executeSteps(steps, on: doc)
        XCTAssertEqual(try liElements.map { try $0.text() }, ["第一章", "第二章"])

        let xpathRule = "//div[@id='chapterlist']/p[position() >= 2 and position() < last()]/a"
        let cssSelector = XPathRuleTranslator.selectorRule(xpathRule)
        XCTAssertEqual(cssSelector, "div#chapterlist p:gt(0):not(:last-child) a")
        let anchors = try HtmlRuleExtractor().select(html, baseUrl: URL(string: "https://example.com")!, listRule: xpathRule)
        XCTAssertEqual(try anchors.map { try $0.text() }, ["Ch 1", "Ch 2"])
    }

    func testAppVersionSemantics() {
        XCTAssertEqual(AppVersion.versionString, "\(AppVersion.epic).\(AppVersion.major).\(AppVersion.minor)")
        XCTAssertEqual(AppVersion.epic, 1)
        XCTAssertEqual(AppVersion.major, 0)
        XCTAssertEqual(AppVersion.minor, 64)
        XCTAssertEqual(AppVersion.build, 65)
        XCTAssertTrue(AppVersion.displayString.contains(AppVersion.versionString))
        XCTAssertTrue(AppVersion.fullDisplayString.contains("Build 65"))
    }
}
