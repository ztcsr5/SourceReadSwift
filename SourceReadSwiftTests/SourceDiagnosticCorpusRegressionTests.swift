import Foundation
import XCTest
@testable import SourceReadSwift

/// Reproductions of the 2026-10-29 diagnostic failures. Responses are local
/// fixtures, not proof of the corresponding remote source's availability.
final class SourceDiagnosticCorpusRegressionTests: XCTestCase {
    func testJSONStringCoercionInsideLibraryPreservesRowObjects() throws {
        let source = BookSource(bookSourceName: "Library JSON", bookSourceUrl: "https://fixture.test",
                                raw: ["jsLib": """
                                function normalizeList(raw) { return JSON.parse(raw).search_tabs[0].data; }
                                """])
        let context = RuleExecutionContext(source: source)
        let object: [String: Any] = ["search_tabs": [["data": [["name": "Book", "id": "123"]]]]]
        let extractor = JSONRuleExtractor(executionContext: context)
        let rows = extractor.list(from: object, rule: "@js:normalizeList(String(result))",
                                  variables: ["source": source])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["id"] as? String, "123")
        XCTAssertEqual(extractor.string(from: object, rule: "@js:result.search_tabs[0].data[0].name"), "Book")
        XCTAssertNil(context.currentJavaScriptError)
    }

    func testJSONCoercionIsNonEnumerableAndDoesNotChangeArraySemantics() throws {
        let runtime = JSCoreRuntime()
        let output = try runtime.evaluate("""
        Object.keys(result).join(',') + '|' + JSON.parse(String(result)).id
        """, variables: ["result": ["id": "123"]]).get()
        XCTAssertEqual(output, "id|123")
        XCTAssertEqual(try runtime.evaluate("String(result)", variables: ["result": ["a", "b"]]).get(), "a,b")
        XCTAssertEqual(try runtime.evaluate("String({id: 1})").get(), "[object Object]")
    }

    func testMultilinePOSTOptionsSurviveRepeatedURLResolution() throws {
        let source = BookSource(bookSourceName: "POST", bookSourceUrl: "https://fixture.test")
        let raw = #"""
        https://fixture.test/book/detail,{
          "body": '{"bookId":"123"}',
          "method": "POST"
        }
        """#
        let context = RuleExecutionContext(source: source)
        let first = DynamicURLResolver.resolve(raw, baseUrl: source.bookSourceUrl, source: source, context: context)
        let second = DynamicURLResolver.resolve(first, baseUrl: source.bookSourceUrl, source: source, context: context)
        let request = SourceRequestBuilder().buildPageRequest(source: source, urlText: second)
        XCTAssertEqual(request.url.absoluteString, "https://fixture.test/book/detail")
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(String(data: try XCTUnwrap(request.body), encoding: .utf8), #"{"bookId":"123"}"#)
    }

    func testURLInDirectiveHeadersCannotReplaceTheRequestURL() throws {
        let source = BookSource(bookSourceName: "Referer", bookSourceUrl: "https://fixture.test")
        let raw = #"""
        https://fixture.test/catalog,{
          "headers": {"Referer":"https://referrer.test/book"},
          "body": "id=123",
          "method": "POST"
        }
        """#
        let resolved = DynamicURLResolver.resolve(raw, baseUrl: source.bookSourceUrl, source: source,
                                                 context: RuleExecutionContext(source: source))
        let request = SourceRequestBuilder().buildPageRequest(source: source, urlText: resolved)
        XCTAssertEqual(request.url.host, "fixture.test")
        XCTAssertEqual(request.url.path, "/catalog")
        XCTAssertEqual(request.headers["Referer"], "https://referrer.test/book")
        XCTAssertEqual(request.method, .post)
    }

    func testMultilinePOSTBookURLRunsAllFourStagesWithTheSameBookID() async throws {
        let network = DiagnosticPOSTFixtureNetwork()
        let source = BookSource(
            bookSourceName: "POST chain", bookSourceUrl: "https://fixture.test",
            searchUrl: "https://fixture.test/search",
            ruleSearch: SourceRule(fields: [
                "bookList": "$.data.bookList", "name": "$.title",
                "bookUrl": #"""
                {{source.getKey()}}/book/detail,{
                  "body": '{"bookId":"{{$.bookId}}"}',
                  "method": "POST"
                }
                """#
            ]),
            ruleBookInfo: SourceRule(fields: [
                "init": "$.data.book", "name": "$.title",
                "tocUrl": #"""
                {{source.getKey()}}/catalog,{
                  "body": '{"bookId":"{{$.bookId}}"}',
                  "method": "POST"
                }
                """#
            ]),
            ruleToc: SourceRule(fields: ["chapterList": "$.data.chapterList[*]", "chapterName": "$.chapterName", "chapterUrl": "$.url"]),
            ruleContent: SourceRule(fields: ["content": "$.body"]),
            header: #"{"Content-Type":"application/json"}"#
        )
        let execution = await LegadoSourceEngine(network: network).runPipelineReport(source: source, keyword: "Fixture", timeout: 5)
        XCTAssertTrue(execution.isSuccess, String(describing: execution.error))
        XCTAssertEqual(execution.result.steps.map(\.stage), [.search, .detail, .toc, .content])
        let requests = await network.requests
        XCTAssertEqual(requests.map { $0.url.path }, ["/search", "/book/detail", "/catalog", "/chapter/1"])
        for request in requests where ["/book/detail", "/catalog"].contains(request.url.path) {
            XCTAssertEqual(request.method, .post)
            let object = try JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any]
            XCTAssertEqual(object?["bookId"] as? String, "123")
        }
    }

    func testBookDetailJSONURLCanParseTheCurrentJSONObject() throws {
        let source = BookSource(bookSourceName: "JSON TOC", bookSourceUrl: "https://fixture.test",
                                ruleBookInfo: SourceRule(fields: [
                                    "name": "$.Data.BookName",
                                    "tocUrl": "@js:var item = JSON.parse(String(result)).Data; '/books/' + item.BookId + '/chapters';"
                                ]))
        let book = searchBook(source: source)
        let response = response(path: "/books/123", body: #"{"Data":{"BookName":"Fixture","BookId":123}}"#)
        let detail = try BookDetailParser(executionContext: RuleExecutionContext(source: source))
            .parse(source: source, book: book, response: response).get()
        XCTAssertEqual(detail.tocUrl, "https://fixture.test/books/123/chapters")
    }

    func testJSONChapterURLCanReadBookTOCURL() throws {
        let source = BookSource(bookSourceName: "LianShang context", bookSourceUrl: "https://fixture.test",
                                ruleToc: SourceRule(fields: [
                                    "chapterList": "$.chapters[*]", "chapterName": "$.name",
                                    "chapterUrl": #"@js:var match = book.tocUrl.match(/chapters\/(\d+)/); match ? '/read/' + match[1] + '/' + result.chapter_id : '';"#
                                ]))
        let book = detailBook(source: source, tocURL: "https://fixture.test/v3/book/chapters/123?page=0")
        let chapters = try ChapterListParser(executionContext: RuleExecutionContext(source: source))
            .parse(source: source, book: book,
                   response: response(path: "/v3/book/chapters/123", body: #"{"chapters":[{"name":"第一章","chapter_id":1},{"name":"第二章","chapter_id":2}]}"#)).get()
        XCTAssertEqual(chapters.map(\.url), ["https://fixture.test/read/123/1", "https://fixture.test/read/123/2"])
    }

    func testHTMLChapterURLAlsoReceivesBookTOCURL() throws {
        let source = BookSource(bookSourceName: "HTML context", bookSourceUrl: "https://fixture.test",
                                ruleToc: SourceRule(fields: [
                                    "chapterList": ".chapter", "chapterName": "text",
                                    "chapterUrl": "@js:book.tocUrl + '/chapter/1'"
                                ]))
        let book = detailBook(source: source, tocURL: "https://fixture.test/catalog")
        let response = SourceResponse(url: URL(string: book.tocUrl!)!, statusCode: 200, headers: [:],
                                      body: #"<html><body><a class="chapter" href="/unused">第一章</a></body></html>"#, data: Data())
        let chapters = try ChapterListParser(executionContext: RuleExecutionContext(source: source))
            .parse(source: source, book: book, response: response).get()
        XCTAssertEqual(chapters.first?.url, "https://fixture.test/catalog/chapter/1")
    }

    func testDiagnosticDoesNotCallAMissingLinkAMissingTitle() {
        let source = BookSource(bookSourceName: "Missing link", bookSourceUrl: "https://fixture.test",
                                ruleToc: SourceRule(fields: ["chapterList": "$.chapters[*]", "chapterName": "$.name", "chapterUrl": "$.url"]))
        let result = ChapterListParser().parse(source: source, book: detailBook(source: source),
                                              response: response(path: "/catalog", body: #"{"chapters":[{"name":"第一章"}]}"#))
        guard case .failure(let error) = result else { return XCTFail("Expected an empty-link failure") }
        XCTAssertTrue(error.displayMessage.contains("标题为空 0"))
        XCTAssertTrue(error.displayMessage.contains("链接为空 1"))
    }

    private func searchBook(source: BookSource) -> SearchBook {
        SearchBook(name: "Fixture", author: nil, coverUrl: nil, bookUrl: "https://fixture.test/books/123",
                   sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil)
    }

    private func detailBook(source: BookSource, tocURL: String = "https://fixture.test/catalog") -> BookDetail {
        BookDetail(name: "Fixture", author: nil, coverUrl: nil, bookUrl: "https://fixture.test/books/123", tocUrl: tocURL,
                   sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil, latestChapter: nil)
    }

    private func response(path: String, body: String) -> SourceResponse {
        SourceResponse(url: URL(string: "https://fixture.test" + path)!, statusCode: 200,
                       headers: ["Content-Type": "application/json"], body: body, data: Data(body.utf8))
    }
}

private actor DiagnosticPOSTFixtureNetwork: SourceNetworkClient {
    private(set) var requests: [SourceRequest] = []

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        requests.append(request)
        let body: String
        switch request.url.path {
        case "/search": body = #"{"data":{"bookList":[{"title":"Fixture","bookId":"123"}]}}"#
        case "/book/detail", "/catalog":
            guard request.method == .post, let data = request.body,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["bookId"] as? String == "123" else {
                return .failure(.empty("POST method/body or book identity was lost"))
            }
            body = request.url.path == "/book/detail"
                ? #"{"data":{"book":{"title":"Fixture","bookId":"123"}}}"#
                : #"{"data":{"chapterList":[{"chapterName":"第一章","url":"/chapter/1"}]}}"#
        case "/chapter/1": body = #"{"body":"第一段正文\n第二段正文"}"#
        default: return .failure(.empty("Unexpected fixture URL: " + request.url.path))
        }
        return .success(SourceResponse(url: request.url, statusCode: 200, headers: ["Content-Type": "application/json"],
                                       body: body, data: Data(body.utf8)))
    }
}
