import XCTest
@testable import SourceReadSwift

final class BookSourceTests: XCTestCase {
    func testDecodeMinimalBookSource() throws {
        let json = """
        {
          "bookSourceName": "Test Source",
          "bookSourceUrl": "https://example.com",
          "searchUrl": "https://example.com/search?q={{keyword}}",
          "ruleSearch": {
            "bookList": ".book",
            "name": ".title@text",
            "bookUrl": "a@href"
          }
        }
        """

        let source = try JSONDecoder().decode(BookSource.self, from: Data(json.utf8))
        XCTAssertEqual(source.bookSourceName, "Test Source")
        XCTAssertEqual(source.ruleSearch?.fields["bookList"], ".book")
    }

    func testSearchRequestInterpolation() {
        let source = BookSource(
            bookSourceName: "Test Source",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/search?q={{keyword}}&page={{page}}"
        )
        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 2
        )

        XCTAssertTrue(request.url.absoluteString.contains("page=2"))
        XCTAssertEqual(request.method, .get)
    }

    func testSearchRequestPreservesHeadDirective() {
        let source = BookSource(
            bookSourceName: "HEAD Source",
            bookSourceUrl: "https://example.com",
            searchUrl: #"https://example.com/health, {"method":"HEAD","headers":{"X-Probe":"1"}}"#
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "ignored",
            page: 1
        )

        XCTAssertEqual(request.method, .head)
        XCTAssertNil(request.body)
        XCTAssertEqual(request.headers["X-Probe"], "1")
    }

    func testEncodeDecodeBookSourceRoundTrip() throws {
        let source = BookSource(
            bookSourceName: "Test Source",
            bookSourceUrl: "https://example.com",
            bookSourceGroup: "Novel",
            weight: 3,
            searchUrl: "https://example.com/search?q={{keyword}}",
            exploreUrl: "https://example.com/rank",
            ruleSearch: SourceRule(fields: [
                "bookList": ".book",
                "name": ".title@text",
                "bookUrl": "a@href"
            ]),
            customConfig: #"{"charset":"gbk"}"#,
            raw: ["webView": "true"]
        )

        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(BookSource.self, from: data)

        XCTAssertEqual(decoded.bookSourceName, "Test Source")
        XCTAssertEqual(decoded.bookSourceGroup, "Novel")
        XCTAssertEqual(decoded.weight, 3)
        XCTAssertEqual(decoded.exploreUrl, "https://example.com/rank")
        XCTAssertEqual(decoded.ruleSearch?.fields["bookList"], ".book")
        XCTAssertEqual(decoded.customConfig, #"{"charset":"gbk"}"#)
        XCTAssertEqual(decoded.raw["webView"], "true")
    }

    func testRequestBuilderReadsHeadersFromCustomConfigAndRawCookie() {
        let source = BookSource(
            bookSourceName: "Header Source",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/search?q={{keyword}}",
            header: #"{"Referer":"https://example.com"}"#,
            customConfig: #"{"headers":{"X-Custom":"1"}}"#,
            raw: ["cookie": "a=b"]
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 1
        )

        XCTAssertEqual(request.headers["Referer"], "https://example.com")
        XCTAssertEqual(request.headers["X-Custom"], "1")
        XCTAssertEqual(request.headers["Cookie"], "a=b")
    }

    func testRequestBuilderResolvesRelativeSearchURLAgainstSourceBase() {
        let source = BookSource(
            bookSourceName: "Relative Source",
            bookSourceUrl: "https://example.com",
            searchUrl: "/search?q={{keyword}}"
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 1
        )

        XCTAssertEqual(request.url.absoluteString, "https://example.com/search?q=test")
    }

    func testRequestBuilderResolvesRelativeSearchURLWithLegadoOptions() {
        let source = BookSource(
            bookSourceName: "Relative Post Source",
            bookSourceUrl: "https://example.com/base/",
            searchUrl: #"search.php?q=fixed, {"method":"POST","body":"q=fixed"}"#
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 1
        )

        XCTAssertEqual(request.url.absoluteString, "https://example.com/base/search.php?q=fixed")
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(String(data: request.body ?? Data(), encoding: .utf8), "q=fixed")
    }

    func testRequestBuilderReadsPostOptionsFromCustomConfig() {
        let source = BookSource(
            bookSourceName: "Post Source",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/api",
            customConfig: #"{"method":"POST","body":"q={{keyword}}","headers":{"Content-Type":"application/x-www-form-urlencoded"}}"#
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 1
        )

        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(String(data: request.body ?? Data(), encoding: .utf8), "q=test")
        XCTAssertEqual(request.headers["Content-Type"], "application/x-www-form-urlencoded")
    }

    func testRequestBuilderReadsBookSourceHeaderAndDictionaryBody() {
        let source = BookSource(
            bookSourceName: "Dictionary Post Source",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/api",
            customConfig: #"{"requestBody":{"q":"{{keyword}}&x","page":"{{page}}"},"bookSourceHeader":{"X-Book":"1"}}"#
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 2
        )

        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(String(data: request.body ?? Data(), encoding: .utf8), "page=2&q=test%26x")
        XCTAssertEqual(request.headers["X-Book"], "1")
    }

    func testRequestBuilderEncodesDictionaryBodyAsJSON() {
        let source = BookSource(
            bookSourceName: "JSON Post Source",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/api",
            customConfig: #"{"headers":{"Content-Type":"application/json"},"body":{"q":"{{keyword}}","page":"{{page}}"}}"#
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 2
        )

        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(String(data: request.body ?? Data(), encoding: .utf8), #"{"page":"2","q":"test"}"#)
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
    }

    func testRequestBuilderUsesJavaUrlEncoderForFormBodyKeywords() {
        let source = BookSource(
            bookSourceName: "Form Body Encoding",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/api",
            customConfig: #"{"headers":{"Content-Type":"application/x-www-form-urlencoded"},"body":"q={{keyword}}&page={{page}}"}"#
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "剑来&x=1",
            page: 2
        )

        XCTAssertEqual(
            String(data: request.body ?? Data(), encoding: .utf8),
            "q=%E5%89%91%E6%9D%A5%26x%3D1&page=2"
        )
    }

    // MARK: - Legado URL-option parity (v1.0.73)

    func testLegadoEscapeEncoderMatchesAndroidEncoderUtils() {
        // EncoderUtils.escape keeps only ASCII letters/digits and emits
        // lowercase hex; `- _ . @ * /` are all escaped, unlike JS `escape()`.
        XCTAssertEqual(LegadoRuleResolver.escapeEncode("剑来"), "%u5251%u6765")
        XCTAssertEqual(LegadoRuleResolver.escapeEncode("a b"), "a%20b")
        XCTAssertEqual(LegadoRuleResolver.escapeEncode("A1-_.@*/"), "A1%2d%5f%2e%40%2a%2f")
        XCTAssertEqual(LegadoRuleResolver.escapeEncode(""), "")
    }

    func testInterpolateHonoursLegadoEscapeCharset() {
        let resolved = LegadoRuleResolver().interpolate(
            "https://example.com/s?q={{keyword}}",
            keyword: "剑来",
            page: 1,
            charset: "escape"
        )
        XCTAssertEqual(resolved, "https://example.com/s?q=%u5251%u6765")
    }

    func testURLDirectiveParsesLegadoWebViewOption() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api, {"webView":true,"webJs":"document.body.innerText","retry":2,"type":"json"}"#
        )
        XCTAssertEqual(directive.urlText, "https://example.com/api")
        XCTAssertEqual(directive.webView, true)
        XCTAssertEqual(directive.webJs, "document.body.innerText")
        XCTAssertEqual(directive.retry, 2)
        XCTAssertEqual(directive.responseType, "json")
        XCTAssertEqual(directive.method, .get)
    }

    func testURLDirectiveTreatsPresentWebViewKeyAsEnabled() {
        // Legado only checks `option.webView?.toString()?.isNotBlank()`, so a
        // literal `false` still turns the WebView path on.
        let directive = SourceURLDirectiveParser().parse(#"https://example.com/api, {"webView":false}"#)
        XCTAssertEqual(directive.webView, true)
    }

    func testURLDirectiveKeepsHTTPVerbTypeAsMethod() {
        let directive = SourceURLDirectiveParser().parse(#"https://example.com/api, {"type":"POST"}"#)
        XCTAssertEqual(directive.method, .post)
        XCTAssertNil(directive.responseType)
    }

    func testSearchRequestCarriesWebViewAndRetryOptions() {
        let source = BookSource(
            bookSourceName: "WebView Option",
            bookSourceUrl: "https://example.com",
            searchUrl: #"https://example.com/api, {"webView":true,"retry":3}"#
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "剑来",
            page: 1
        )

        XCTAssertTrue(request.webView)
        XCTAssertEqual(request.retry, 3)
        XCTAssertNil(request.webJs)
    }

    func testSearchRequestPicksUpEscapeCharsetFromURLJSON() {
        let source = BookSource(
            bookSourceName: "Escape Charset",
            bookSourceUrl: "https://example.com",
            searchUrl: #"https://example.com/search?q={{keyword}}, {"charset":"escape"}"#
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "剑来",
            page: 1
        )

        XCTAssertEqual(request.expectedCharset, "escape")
        XCTAssertTrue(
            request.url.absoluteString.contains("q=%25u5251%25u6765"),
            "escape output must survive URL canonicalisation as a literal %: \(request.url.absoluteString)"
        )
    }

    func testRequestBuilderEscapesKeywordInsideJSONTextBody() {
        let source = BookSource(
            bookSourceName: "JSON Text Body",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/api",
            customConfig: #"{"headers":{"Content-Type":"application/json"},"body":"{\"q\":\"{{keyword}}\"}"}"#
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "he said \"hi\"",
            page: 1
        )

        let data = request.body ?? Data()
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        XCTAssertEqual(object?["q"] as? String, "he said \"hi\"")
    }

    func testDirectiveBodyOverridesRawBody() {
        let source = BookSource(
            bookSourceName: "Post Source",
            bookSourceUrl: "https://example.com",
            searchUrl: #"https://example.com/api@Body:q=directive"#,
            raw: ["body": "q=raw", "method": "POST"]
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 1
        )

        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(String(data: request.body ?? Data(), encoding: .utf8), "q=directive")
    }

    func testRequestBuilderReadsCharsetFromCustomConfig() {
        let source = BookSource(
            bookSourceName: "Charset Source",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/search",
            customConfig: #"{"charset":"gbk"}"#
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 1
        )

        XCTAssertEqual(request.expectedCharset, "gbk")
    }

    func testRequestBuilderReadsCharsetFromURLDirectiveOptions() {
        let source = BookSource(
            bookSourceName: "Directive Charset Source",
            bookSourceUrl: "https://example.com",
            searchUrl: #"https://example.com/search?q={{keyword}},{"charset":"gbk"}"#
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 1
        )

        XCTAssertEqual(request.url.absoluteString, "https://example.com/search?q=test")
        XCTAssertEqual(request.expectedCharset, "gbk")
    }

    func testRequestBuilderUsesDirectiveTimeoutAndClampsValue() {
        let source = BookSource(
            bookSourceName: "Timeout Source",
            bookSourceUrl: "https://example.com",
            searchUrl: #"https://example.com/search,{"timeoutMs":2500}"#,
            customConfig: #"{"timeout":1}"#,
            raw: ["timeout": "0.5"]
        )
        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 1
        )
        XCTAssertEqual(request.timeout, 2.5, accuracy: 0.001)

        let clamped = SourceRequestBuilder().buildPageRequest(
            source: source,
            urlText: #"https://example.com/page,{"timeout":999999}"#
        )
        XCTAssertEqual(clamped.timeout, 120, accuracy: 0.001)
    }

    func testRequestBuilderPrefersCustomConfigTimeoutOverRawTimeout() {
        let source = BookSource(
            bookSourceName: "Timeout Precedence",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/search",
            customConfig: #"{"timeoutMs":2000}"#,
            raw: ["timeout": "8"]
        )
        let request = SourceRequestBuilder().buildPageRequest(source: source, urlText: source.searchUrl!)
        XCTAssertEqual(request.timeout, 2, accuracy: 0.001)
    }

    func testRequestBuilderDefaultsToThePipelineStageBudget() {
        let source = BookSource(
            bookSourceName: "Default Timeout",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/search"
        )
        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 1
        )
        XCTAssertEqual(SourceRequestBuilder.defaultTimeout, 20, accuracy: 0.001)
        XCTAssertEqual(request.timeout, SourceRequestBuilder.defaultTimeout, accuracy: 0.001)
    }

    func testRequestBuilderReadsLegadoTypeDataAndUserAgentAliases() {
        let source = BookSource(
            bookSourceName: "Legado Alias Source",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/api",
            customConfig: #"{"type":"POST","data":{"q":"{{keyword}}","page":"{{page}}"},"ua":"AliasUA/1.0"}"#
        )

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "test",
            page: 3
        )

        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(String(data: request.body ?? Data(), encoding: .utf8), "page=3&q=test")
        XCTAssertEqual(request.headers["User-Agent"], "AliasUA/1.0")
        XCTAssertEqual(request.headers["Referer"], "https://example.com/")
        XCTAssertEqual(request.headers["Origin"], "https://example.com")
    }

    func testDecodeLegacyLegadoBookSourceFields() throws {
        let json = """
        {
          "bookSourceName": "Legacy Source",
          "bookSourceUrl": "https://example.com",
          "bookSourceGroup": "legacy",
          "enabled": "y",
          "serialNumber": 9,
          "ruleSearchUrl": "https://example.com/search/searchKey/searchPage|charset=gbk@q=searchKey&page=searchPage",
          "ruleSearchList": ".result",
          "ruleSearchName": ".name",
          "ruleSearchAuthor": ".author",
          "ruleSearchNoteUrl": "a@href",
          "ruleBookInfoInit": "#main",
          "ruleBookName": "h1",
          "ruleBookAuthor": ".author",
          "ruleIntroduce": ".intro",
          "ruleChapterList": ".chapter",
          "ruleChapterName": "a",
          "ruleContentUrl": "a@href",
          "ruleBookContent": ".content@html",
          "ruleBookContentReplace": "ads##",
          "ruleContentUrlNext": ".next@href",
          "httpUserAgent": "LegacyUA/1.0"
        }
        """

        let source = try JSONDecoder().decode(BookSource.self, from: Data(json.utf8))

        XCTAssertEqual(source.bookSourceGroup, "legacy")
        XCTAssertTrue(source.enabled)
        XCTAssertEqual(source.weight, 9)
        XCTAssertEqual(source.searchUrl, #"https://example.com/search/{{key}}/{{page}},{"body":"q={{key}}&page={{page}}","charset":"gbk","method":"POST"}"#)
        XCTAssertEqual(source.ruleSearch?.fields["bookList"], ".result")
        XCTAssertEqual(source.ruleSearch?.fields["name"], ".name")
        XCTAssertEqual(source.ruleSearch?.fields["bookUrl"], "a@href")
        XCTAssertEqual(source.ruleBookInfo?.fields["name"], "h1")
        XCTAssertEqual(source.ruleBookInfo?.fields["init"], "#main")
        XCTAssertEqual(source.ruleBookInfo?.fields["intro"], ".intro")
        XCTAssertEqual(source.ruleToc?.fields["chapterList"], ".chapter")
        XCTAssertEqual(source.ruleToc?.fields["chapterUrl"], "a@href")
        XCTAssertEqual(source.ruleContent?.fields["content"], ".content@html")
        XCTAssertEqual(source.ruleContent?.fields["replaceRegex"], "ads##")
        XCTAssertEqual(source.ruleContent?.fields["nextContentUrl"], ".next@href")

        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "abc",
            page: 2
        )

        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.expectedCharset, "gbk")
        XCTAssertEqual(request.headers["User-Agent"], "LegacyUA/1.0")
        XCTAssertEqual(String(data: request.body ?? Data(), encoding: .utf8), "q=abc&page=2")
    }

    func testDecodeRuleObjectStoredAsJSONString() throws {
        let json = #"""
        {
          "bookSourceName": "JSONString Rule Source",
          "bookSourceUrl": "https://example.com",
          "searchUrl": "https://example.com/search?q={{key}}",
          "ruleSearch": "{\"bookList\":\".item\",\"name\":\".title\",\"bookUrl\":\"a@href\"}"
        }
        """#

        let source = try JSONDecoder().decode(BookSource.self, from: Data(json.utf8))

        XCTAssertEqual(source.ruleSearch?.fields["bookList"], ".item")
        XCTAssertEqual(source.ruleSearch?.fields["name"], ".title")
        XCTAssertEqual(source.ruleSearch?.fields["bookUrl"], "a@href")
        XCTAssertNil(source.ruleSearch?.raw)
    }

    func testRuleBookContentObjectIsKeptStructured() throws {
        let json = """
        {
          "bookSourceName": "Structured Content Source",
          "bookSourceUrl": "https://example.com",
          "searchUrl": "https://example.com/search?q={{key}}",
          "ruleBookContent": {
            "content": ".content@html",
            "nextContentUrl": ".next@href"
          }
        }
        """

        let source = try JSONDecoder().decode(BookSource.self, from: Data(json.utf8))

        XCTAssertEqual(source.ruleContent?.fields["content"], ".content@html")
        XCTAssertEqual(source.ruleContent?.fields["nextContentUrl"], ".next@href")
    }

    // MARK: - Format identity

    func testSourceFormatUsesExplicitRawMarker() {
        let source = BookSource(
            bookSourceName: "花火源",
            bookSourceUrl: "https://format.example.com",
            raw: ["sourceFormat": "huahuo"]
        )

        XCTAssertEqual(source.sourceFormat, .huahuo)
        XCTAssertEqual(source.displayBadges.first, "花火")
    }

    func testSourceFormatFallsBackToXbsOrigin() {
        let source = BookSource(
            bookSourceName: "香色源",
            bookSourceUrl: "https://xbs.example.com",
            raw: ["xbsOrigin": "true"]
        )

        XCTAssertEqual(source.sourceFormat, .xbs)
    }

    func testSourceFormatRecognizesBuiltinBrowserSource() {
        let source = BookSource(
            bookSourceName: "内置导航源",
            bookSourceUrl: BuiltinBrowserSourceProvider.browserSourceUrl
        )

        XCTAssertEqual(source.sourceFormat, .builtin)
    }

    func testSourceFormatDefaultsToLegado() {
        let source = BookSource(
            bookSourceName: "普通源",
            bookSourceUrl: "https://plain.example.com"
        )

        XCTAssertEqual(source.sourceFormat, .legado)
    }

    func testDisplayBadgesIncludeSearchCapabilityOnlyWhenSearchRuleExists() {
        let searchable = BookSource(
            bookSourceName: "可搜索源",
            bookSourceUrl: "https://searchable.example.com",
            ruleSearch: SourceRule(fields: ["bookList": ".item"])
        )
        let browseOnly = BookSource(
            bookSourceName: "仅浏览源",
            bookSourceUrl: "https://browse.example.com"
        )

        XCTAssertEqual(searchable.displayBadges, ["Legado", "可搜索"])
        XCTAssertEqual(browseOnly.displayBadges, ["Legado"])
    }

    func testSourceFormatSurvivesEncodeDecode() throws {
        let source = BookSource(
            bookSourceName: "海阔源",
            bookSourceUrl: "https://roundtrip.example.com",
            raw: ["sourceFormat": "haikuo"]
        )

        let decoded = try JSONDecoder().decode(BookSource.self, from: JSONEncoder().encode(source))

        XCTAssertEqual(decoded.sourceFormat, .haikuo)
        XCTAssertEqual(decoded.raw["sourceFormat"], "haikuo")
    }

    func testUpdatingRulesAndEnabledPreserveSourceFormat() {
        let source = BookSource(
            bookSourceName: "花火更新源",
            bookSourceUrl: "https://update.example.com",
            searchUrl: "https://update.example.com/search?q={{key}}",
            ruleSearch: SourceRule(fields: ["bookList": ".old"]),
            raw: ["sourceFormat": "huahuo"]
        )

        let rulesUpdated = source.updatingRules(
            searchURL: "https://update.example.com/search?q={{key}}",
            search: #"{"bookList":".new"}"#,
            detail: "",
            toc: "",
            content: ""
        )
        let disabled = source.updatingEnabled(false)

        XCTAssertEqual(rulesUpdated.sourceFormat, .huahuo)
        XCTAssertEqual(rulesUpdated.ruleSearch?.fields["bookList"], ".new")
        XCTAssertEqual(disabled.sourceFormat, .huahuo)
        XCTAssertFalse(disabled.enabled)
    }
}
