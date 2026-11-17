import Foundation
import XCTest
@testable import SourceReadSwift

/// Replays shared rule shapes over authored content. No imported script or live site is used.
final class SourceParserBundleCompatibilityTests: XCTestCase {
    func testHTMLSearchFieldsKeepTheirSelectedElementAndChainedText() throws {
        let body = """
        <section class="book" data-id="/book/1" data-title="One"><a>First</a><i>A</i><i>B</i></section>
        <section class="book" data-id="/book/2" data-title="Two"><a>Second</a><i>C</i><i>D</i></section>
        """
        let source = BookSource(bookSourceName: "HTML row scope", bookSourceUrl: "https://catalog.invalid",
            ruleSearch: SourceRule(fields: ["bookList": ".book", "name": "@js:result.attr('data-title')",
                "bookUrl": "@js:result.attr('data-id')", "kind": "a@text@js:result + ' text'",
                "intro": "i@js:result.size() + ':' + result.last().text()",
                "author": "@js:body.indexOf('data-title=\"Two\"') >= 0 ? 'Page' : 'Missing'"]))
        let response = SourceResponse(url: try XCTUnwrap(URL(string: "https://catalog.invalid/search")),
            statusCode: 200, headers: ["Content-Type": "text/html"], body: body, data: Data(body.utf8))
        let books = try SearchResultParser().parse(source: source, response: response).get()
        XCTAssertEqual(books.map(\.name), ["One", "Two"])
        XCTAssertEqual(books.map(\.bookUrl), ["https://catalog.invalid/book/1", "https://catalog.invalid/book/2"])
        XCTAssertEqual(books.map(\.kind), ["First text", "Second text"])
        XCTAssertEqual(books.map(\.intro), ["2:B", "2:D"])
        XCTAssertEqual(books.map(\.author), ["Page", "Page"])
    }

    func testHTMLDirectoryFieldsKeepTheirSelectedElement() throws {
        let body = """
        <section data-time="Today">
        <div class="chapter" data-url="/chapter/1" data-title="First" data-vip="false"><b>100</b></div>
        <div class="chapter" data-url="/chapter/2" data-title="Second" data-vip="true"><b>200</b></div>
        </section>
        """
        let source = BookSource(bookSourceName: "HTML directory scope", bookSourceUrl: "https://catalog.invalid",
            ruleToc: SourceRule(fields: ["chapterList": ".chapter", "chapterName": "@js:result.attr('data-title')",
                "chapterUrl": "@js:result.attr('data-url')", "isVip": "@js:result.attr('data-vip')",
                "wordCount": "b@text@js:result + ' words'", "updateTime": "@js:result.attr('data-time')"]))
        let book = BookDetail(name: "Fixture", author: nil, coverUrl: nil, bookUrl: "https://catalog.invalid/book/1",
            sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil, latestChapter: nil)
        let response = SourceResponse(url: try XCTUnwrap(URL(string: "https://catalog.invalid/toc")),
            statusCode: 200, headers: ["Content-Type": "text/html"], body: body, data: Data(body.utf8))
        let chapters = try ChapterListParser().parse(source: source, book: book, response: response).get()
        XCTAssertEqual(chapters.map(\.title), ["First", "Second"])
        XCTAssertEqual(chapters.map(\.url), ["https://catalog.invalid/chapter/1", "https://catalog.invalid/chapter/2"])
        XCTAssertEqual(chapters.map(\.isVip), [false, true])
        XCTAssertEqual(chapters.map(\.wordCount), ["100 words", "200 words"])
        XCTAssertEqual(chapters.map(\.updateTime), ["Today", "Today"])
    }

    func testJavaBridgeReadsTheSelectedSearchRowAfterATemplateChain() throws {
        let body = #"{"tag":"页面级标签","items":[{"name":"规则样本","tag":"条目级标签","url":"/edition"}]}"#
        let source = BookSource(
            bookSourceName: "Row scope",
            bookSourceUrl: "https://catalog.invalid",
            ruleSearch: SourceRule(fields: [
                "bookList": "$.items[*]",
                "name": "$.name",
                "bookUrl": "$.url",
                "kind": #"{{$.name}}<js>String(result) + ': ' + java.getString('$.tag');</js>"#
            ])
        )
        let response = makeJSONResponse(path: "/search", body: body)
        let books = try SearchResultParser().parse(source: source, response: response, keyword: "规则样本").get()
        XCTAssertEqual(books.map(\.kind), ["规则样本: 条目级标签"])
    }

    func testRuleDocumentDoesNotLeakBetweenJavaScriptEvaluations() throws {
        let runtime = JSCoreRuntime()
        let rule = "java.getString('$.tag')"
        let page = #"{"tag":"页面"}"#
        let row = try runtime.evaluate(rule, variables: [
            "src": page, JSCoreRuntime.ruleDocumentBinding: ["tag": "条目"]
        ]).get()
        let next = try runtime.evaluate(rule, variables: ["src": page]).get()
        XCTAssertEqual(row, "条目")
        XCTAssertEqual(next, "页面")
    }

    func testInlineEnvelopesRunFromSearchToTwoDifferentChapterBodies() async throws {
        let source = BookSource(
            bookSourceName: "Inline edition fixture",
            bookSourceUrl: "https://catalog.invalid",
            searchUrl: "https://catalog.invalid/search",
            ruleSearch: SourceRule(fields: [
                "bookList": "$.items[*]",
                "name": "$.name",
                "bookUrl": "<js>'data:detailsUrl;base64,' + java.base64Encode(JSON.stringify(result));</js>"
            ]),
            ruleBookInfo: SourceRule(fields: [
                "init": "<js>JSON.parse(String(result)).details;</js>",
                "name": "$.title",
                "tocUrl": "<js>var entry = JSON.parse(String(result)); 'data:catalogUrl;base64,' + java.base64Encode(JSON.stringify(entry.directory));</js>"
            ]),
            ruleToc: SourceRule(fields: [
                "chapterList": "<js>JSON.parse(String(result)).chapters;</js>",
                "chapterName": "@js: java.getString('$.title')",
                "chapterUrl": "<js>'data:chapterUrl;base64,' + java.base64Encode(JSON.stringify(result));</js>"
            ]),
            ruleContent: SourceRule(fields: ["content": "$.prose"])
        )
        let body = #"{"items":[{"name":"远山样本","details":{"title":"远山样本·详情","directory":{"chapters":[{"title":"第一章","prose":"第一章的试读正文。"},{"title":"第二章","prose":"第二章的试读正文。"}]}}}]}"#
        let engine = LegadoSourceEngine(network: InlineEnvelopeFixtureNetwork(searchResponse: makeJSONResponse(path: "/search", body: body)))

        let search = try await engine.searchBooks(source: source, keyword: "远山样本", page: 1).get()
        let book = try XCTUnwrap(search.first)
        XCTAssertTrue(book.bookUrl.hasPrefix("data:detailsUrl;base64,"))

        let detail = try await engine.getBookDetail(source: source, book: book).get()
        XCTAssertEqual(detail.name, "远山样本·详情")
        XCTAssertTrue(try XCTUnwrap(detail.tocUrl).hasPrefix("data:catalogUrl;base64,"))

        let chapters = try await engine.getChapterList(source: source, book: detail).get()
        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(Set(chapters.map(\.url)).count, 2)
        let firstChapter = try XCTUnwrap(chapters.first)
        let secondChapter = try XCTUnwrap(chapters.last)
        let first = try await engine.getContent(source: source, chapter: firstChapter).get()
        let second = try await engine.getContent(source: source, chapter: secondChapter).get()
        XCTAssertEqual(first.paragraphs, ["第一章的试读正文。"], describeInlinePayload(firstChapter))
        XCTAssertEqual(second.paragraphs, ["第二章的试读正文。"], describeInlinePayload(secondChapter))
    }

    func testTypedInlineCatalogSurvivesBookDetailAndDirectoryHandoff() async throws {
        let source = BookSource(bookSourceName: "Typed catalog fixture", bookSourceUrl: "https://catalog.invalid",
            ruleBookInfo: SourceRule(fields: ["name": "$.title",
                "tocUrl": #"<js>'data:;base64,' + java.base64Encode(JSON.stringify(result.catalog)) + ',{"type":"catalogUrl"}';</js>"#]),
            ruleToc: SourceRule(fields: ["chapterList": "<js>JSON.parse(java.hexDecodeToString(result));</js>$.chapters[*]",
                "chapterName": "$.title", "chapterUrl": "$.url"]))
        let response = makeJSONResponse(path: "/edition",
            body: #"{"title":"目录样本","catalog":{"chapters":[{"title":"第一章","url":"https://catalog.invalid/1"},{"title":"第二章","url":"https://catalog.invalid/2"}]}}"#)
        let book = SearchBook(name: "目录样本", author: nil, coverUrl: nil, bookUrl: response.url.absoluteString,
            sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl)
        let engine = LegadoSourceEngine(network: InlineEnvelopeFixtureNetwork(searchResponse: response))
        let detail = try await engine.getBookDetail(source: source, book: book).get()
        let address = try XCTUnwrap(detail.tocUrl)
        XCTAssertTrue(address.hasSuffix(#",{"type":"catalogUrl"}"#), "The saved address must preserve the rule option")
        let chapters = try await engine.getChapterList(source: source, book: detail).get()
        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(chapters.map(\.url), ["https://catalog.invalid/1", "https://catalog.invalid/2"])
    }

    func testSeparateCatalogScriptReceivesTheInterpolatedPathAndGetsItsChapterList() async throws {
        let source = BookSource(bookSourceName: "Templated catalog", bookSourceUrl: "https://catalog.invalid",
            ruleBookInfo: SourceRule(fields: ["name": "$.title", "tocUrl": #"""
                /catalog?edition={{$.details.id}}&format={{$.details.format}}
                <js>'data:;base64,' + java.base64Encode(result) + ',{"type":"catalogUrl"}';</js>
                """#]),
            ruleToc: SourceRule(fields: ["chapterList": #"""
                <js>JSON.parse(java.ajax('https://catalog.invalid' + java.hexDecodeToString(result)));</js>$.chapters[*]
                """#, "chapterName": "$.title", "chapterUrl": "$.url"]))
        let detailResponse = makeJSONResponse(path: "/edition", body: #"{"title":"目录样本","details":{"id":7,"format":"text"}}"#)
        let catalogPath = "/catalog?edition=7&format=text"
        let chapterResponse = makeJSONResponse(path: catalogPath,
            body: #"{"chapters":[{"title":"第一章","url":"https://catalog.invalid/1"},{"title":"第二章","url":"https://catalog.invalid/2"}]}"#)
        let network = InlineEnvelopeFixtureNetwork(searchResponse: detailResponse, extraResponses: [chapterResponse])
        let engine = LegadoSourceEngine(network: network)
        let book = SearchBook(name: "目录样本", author: nil, coverUrl: nil, bookUrl: detailResponse.url.absoluteString,
            sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl)
        let detail = try await engine.getBookDetail(source: source, book: book).get()
        let address = try XCTUnwrap(detail.tocUrl)
        XCTAssertEqual(address, "data:;base64," + Data(catalogPath.utf8).base64EncodedString() + #",{"type":"catalogUrl"}"#)
        let chapters = try await engine.getChapterList(source: source, book: detail).get()
        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(chapters.map(\.url), ["https://catalog.invalid/1", "https://catalog.invalid/2"])
    }

    func testAlreadyEncodedInlineCatalogOptionDecodesOnlyTheSuffix() async throws {
        let source = BookSource(bookSourceName: "Encoded inline fixture", bookSourceUrl: "https://catalog.invalid")
        let payload = Data([0xFF, 0xEF]).base64EncodedString().replacingOccurrences(of: "/", with: "%2F")
        let request = SourceRequestBuilder().buildPageRequest(source: source,
            urlText: "data:;base64," + payload + ",%7B%22type%22:%22catalogUrl%22%7D")
        XCTAssertTrue(request.shouldReturnInlineHex)
        XCTAssertTrue(request.url.absoluteString.hasSuffix(payload))
        let response = try await URLSessionSourceNetworkClient().load(request).get()
        XCTAssertEqual(response.body, "ffef")
    }

    func testInlineDataDecodesEscapedBase64AndKeepsItsDeclaredType() async throws {
        let json = #"{"title":"节选"}"#
        let escaped = Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "%3D")
            .replacingOccurrences(of: "+", with: "%2B")
            .replacingOccurrences(of: "/", with: "%2F")
        let url = try XCTUnwrap(URL(string: "data:application/json;BASE64," + escaped))
        let request = SourceRequest(url: url, method: .get, headers: [:], body: nil, expectedCharset: nil, timeout: 1)
        let loaded = try await URLSessionSourceNetworkClient().load(request).get()
        XCTAssertEqual(loaded.body, json)
        XCTAssertTrue(loaded.headers["Content-Type"]?.hasPrefix("application/json") == true)
    }

    func testJSONTextEnvelopeIsUnwrappedBeforeApplyingTheContentRule() throws {
        let document = #"{"prose":"通过书源选择器提取的实际正文。"}"#
        let bytes = try JSONEncoder().encode(document)
        let source = BookSource(bookSourceName: "Wrapped JSON",
                                bookSourceUrl: "https://catalog.invalid",
                                ruleContent: SourceRule(fields: ["content": "$.prose"]))
        let chapter = BookChapter(title: "节选", url: "https://catalog.invalid/text",
                                  bookUrl: "https://catalog.invalid/title", index: 0)
        let response = SourceResponse(url: try XCTUnwrap(URL(string: chapter.url)), statusCode: 200,
            headers: ["Content-Type": "application/json"], body: String(decoding: bytes, as: UTF8.self), data: bytes)
        let content = try ContentParser().parse(source: source, chapter: chapter, response: response).get()
        XCTAssertEqual(content.paragraphs, ["通过书源选择器提取的实际正文。"])
    }

    func testRawInlineJSONSeparatorIsNotTreatedAsHTTPRequestOptions() async throws {
        let source = BookSource(bookSourceName: "Local data", bookSourceUrl: "https://catalog.invalid")
        let request = SourceRequestBuilder().buildPageRequest(source: source,
            urlText: #"data:application/json,{"method":"POST","body":"https://embedded.invalid/article?z=2&a=1"}"#)
        XCTAssertEqual(request.url.scheme, "data")
        XCTAssertEqual(request.method, .get)
        XCTAssertNil(request.body)
        guard request.url.scheme == "data" else { return }
        XCTAssertFalse(LegadoSourceEngine.shouldForceWebView(for: SourceRequest(
            url: request.url, method: .get, headers: [:], body: nil, expectedCharset: nil, timeout: 1, webView: true)))
        let loaded = try await URLSessionSourceNetworkClient().load(request).get()
        XCTAssertEqual(ResponseFormatDetector.jsonObject(from: loaded.body) as? [String: String],
                       ["method": "POST", "body": "https://embedded.invalid/article?z=2&a=1"])
    }

    func testMalformedInlineBase64IsNotReturnedAsSuccessfulContent() async throws {
        let url = try XCTUnwrap(URL(string: "data:chapterUrl;base64,not%20base64!"))
        let request = SourceRequest(url: url, method: .get, headers: [:], body: nil, expectedCharset: nil, timeout: 1)
        let loaded = await URLSessionSourceNetworkClient().load(request)
        guard case .failure(.rule) = loaded else {
            return XCTFail("A damaged inline chapter must be a parse error")
        }
    }

    private func makeJSONResponse(path: String, body: String) -> SourceResponse {
        SourceResponse(url: URL(string: "https://catalog.invalid" + path)!,
                       statusCode: 200, headers: ["Content-Type": "application/json"],
                       body: body, data: Data(body.utf8))
    }

    private func describeInlinePayload(_ chapter: BookChapter) -> String {
        guard let url = URL(string: chapter.url),
              case .success(let response) = SourceInlineEnvelope.response(for: url) else { return "Invalid fixture envelope" }
        let object = ResponseFormatDetector.jsonObject(from: response.body)
        return "Fixture body starts with \(response.body.prefix(1)); JSON root is \(object.map { String(describing: type(of: $0)) } ?? "not JSON")"
    }
}

private struct InlineEnvelopeFixtureNetwork: SourceNetworkClient {
    let searchResponse: SourceResponse
    var extraResponses: [SourceResponse] = []

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        if request.url == searchResponse.url { return .success(searchResponse) }
        if let response = extraResponses.first(where: { $0.url == request.url }) { return .success(response) }
        if request.url.scheme == "data" { return await URLSessionSourceNetworkClient().load(request) }
        return .failure(.network("Offline fixture rejected an unexpected request"))
    }
}
