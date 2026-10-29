import Foundation
import XCTest
@testable import SourceReadSwift

final class SourceURLBodyJSRegressionTests: XCTestCase {
    func testURLDirectiveKeepsBodyJSSeparateFromURLJS() throws {
        let directive = SourceURLDirectiveParser().parse(try encodedURL("https://fixture.test/search", script: "result.toUpperCase()"))
        XCTAssertEqual(directive.urlText, "https://fixture.test/search")
        XCTAssertEqual(directive.bodyJavaScript, "result.toUpperCase()")
        XCTAssertNil(directive.urlJavaScript)
        XCTAssertEqual(directive.method, .get)
    }

    func testURLBodyJSRunsSearchDetailTOCAndContent() async throws {
        let bookURL = try encodedURL("https://fixture.test/book/1", script: "result.replace('ENCODED_TITLE','Fixture')")
        let tocURL = try encodedURL("https://fixture.test/catalog", script: "JSON.stringify({chapters:JSON.parse(result).rawChapters})")
        let chapterURL = try encodedURL("https://fixture.test/chapter/1", script: "result.replace('ENCODED_CONTENT','正文第一段')")
        let source = BookSource(
            bookSourceName: "URL body chain", bookSourceUrl: "https://fixture.test",
            searchUrl: try encodedURL("https://fixture.test/search", script: "JSON.stringify({books:JSON.parse(result).rawBooks})"),
            ruleSearch: SourceRule(fields: ["bookList": "$.books[*]", "name": "$.name", "bookUrl": "$.url"]),
            ruleBookInfo: SourceRule(fields: ["name": "$.title", "tocUrl": "$.toc"]),
            ruleToc: SourceRule(fields: ["chapterList": "$.chapters[*]", "chapterName": "$.name", "chapterUrl": "$.url"]),
            ruleContent: SourceRule(fields: ["content": "$.body"])
        )
        let network = URLBodyFixtureNetwork(responses: [
            "/search": try json(["rawBooks": [["name": "Fixture", "url": bookURL]]]),
            "/book/1": try json(["title": "ENCODED_TITLE", "toc": tocURL]),
            "/catalog": try json(["rawChapters": [["name": "第一章", "url": chapterURL]]]),
            "/chapter/1": #"{"body":"ENCODED_CONTENT"}"#
        ])
        let execution = await LegadoSourceEngine(network: network).runPipelineReport(source: source, keyword: "Fixture", timeout: 5)
        XCTAssertTrue(execution.isSuccess, String(describing: execution.error))
        XCTAssertEqual(execution.result.steps.map(\.stage), [.search, .detail, .toc, .content])
        XCTAssertTrue(execution.result.steps.allSatisfy { $0.status == .passed })
        let paths = await network.paths
        XCTAssertEqual(paths, ["/search", "/book/1", "/catalog", "/chapter/1"])
    }

    func testURLBodyJSUsesSearchGlobalsAndLoadsLibraryOnce() async throws {
        let source = BookSource(
            bookSourceName: "Body library", bookSourceUrl: "https://fixture.test",
            searchUrl: try encodedURL("https://fixture.test/search", script: "JSON.stringify({books:[{name:libraryTitle(),url:'/book/1'}]})"),
            ruleSearch: SourceRule(fields: ["bookList": "$.books[*]", "name": "$.name", "bookUrl": "$.url"]),
            raw: ["jsLib": """
            java.put('libraryLoads', Number(java.get('libraryLoads') || 0) + 1);
            function libraryTitle() { return key + ':' + page; }
            """]
        )
        let engine = LegadoSourceEngine(network: URLBodyFixtureNetwork(responses: ["/search": "{}"] ))
        let books = try await engine.searchBooks(source: source, keyword: "Fixture", page: 2).get()
        XCTAssertEqual(books.first?.name, "Fixture:2")
        XCTAssertEqual(engine.persistentState(for: source).get("libraryLoads"), "1")
    }

    func testFailingURLBodyJSCannotSilentlyPassWithTheOriginalBody() async throws {
        let source = BookSource(bookSourceName: "Broken body", bookSourceUrl: "https://fixture.test",
                                searchUrl: try encodedURL("https://fixture.test/search", script: "throw new Error('body failure')"),
                                ruleSearch: SourceRule(fields: ["bookList": "$.books[*]", "name": "$.name", "bookUrl": "$.url"]))
        let network = URLBodyFixtureNetwork(responses: ["/search": #"{"books":[{"name":"Fixture","url":"/book/1"}]}"#])
        let result = await LegadoSourceEngine(network: network).searchBooks(source: source, keyword: "Fixture", page: 1)
        guard case .failure(let error) = result else { return XCTFail("A failed transform must fail this stage") }
        XCTAssertTrue(error.displayMessage.contains("bodyJs"))
        XCTAssertTrue(error.displayMessage.contains("body failure"))
    }

    func testEmptyURLBodyJSDoesNotFallBackToOriginalSearchResults() async throws {
        let source = BookSource(bookSourceName: "Empty body", bookSourceUrl: "https://fixture.test",
                                searchUrl: try encodedURL("https://fixture.test/search", script: "''"),
                                ruleSearch: SourceRule(fields: ["bookList":"$.books[*]", "name":"$.name", "bookUrl":"$.url"]))
        let network = URLBodyFixtureNetwork(responses: ["/search": #"{"books":[{"name":"Fixture","url":"/book/1"}]}"#])
        guard case .failure = await LegadoSourceEngine(network: network).searchBooks(source: source, keyword: "Fixture", page: 1) else {
            return XCTFail("An explicitly empty transform cannot pass with the old body")
        }
    }

    func testURLBodyJSRunsExploreAndBothPaginationPaths() async throws {
        let normalizer = "JSON.stringify(JSON.parse(result).payload)"
        let catalogURL = try encodedURL("https://fixture.test/catalog", script: normalizer)
        let nextCatalogURL = try encodedURL("https://fixture.test/catalog/2", script: normalizer)
        let chapterURL = try encodedURL("https://fixture.test/chapter/1", script: normalizer)
        let nextContentURL = try encodedURL("https://fixture.test/chapter/1/2", script: normalizer)
        let source = BookSource(bookSourceName: "Pagination body", bookSourceUrl: "https://fixture.test",
            ruleExplore: SourceRule(fields: ["bookList":"$.books[*]", "name":"$.name", "bookUrl":"$.url"]),
            ruleBookInfo: SourceRule(fields: ["name":"$.title", "tocUrl":"$.toc"]),
            ruleToc: SourceRule(fields: ["chapterList":"$.chapters[*]", "chapterName":"$.name", "chapterUrl":"$.url", "nextTocUrl":"$.next"]),
            ruleContent: SourceRule(fields: ["content":"$.body", "nextContentUrl":"$.next"]))
        let network = URLBodyFixtureNetwork(responses: [
            "/explore": try json(["payload":["books":[["name":"Fixture", "url":"/book/1"]]]]),
            "/book/1": try json(["title":"Fixture", "toc":catalogURL]),
            "/catalog": try json(["payload":["chapters":[["name":"第一章", "url":chapterURL]], "next":nextCatalogURL]]),
            "/catalog/2": try json(["payload":["chapters":[["name":"第二章", "url":"/chapter/2"]], "next":""]]),
            "/chapter/1": try json(["payload":["body":"正文第一页。", "next":nextContentURL]]),
            "/chapter/1/2": try json(["payload":["body":"正文第二页。", "next":""]])
        ])
        let engine = LegadoSourceEngine(network: network)
        let books = try await engine.exploreBooks(source: source, url: encodedURL("https://fixture.test/explore", script: normalizer), page: 1).get()
        let detail = try await engine.getBookDetail(source: source, book: XCTUnwrap(books.first)).get()
        let chapters = try await engine.getChapterList(source: source, book: detail, maxPages: 3).get()
        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章"])
        let content = try await engine.getContent(source: source, chapter: XCTUnwrap(chapters.first), maxPages: 3).get()
        XCTAssertTrue(content.paragraphs.joined().contains("正文第一页。"))
        XCTAssertTrue(content.paragraphs.joined().contains("正文第二页。"))
        let paths = await network.paths
        XCTAssertEqual(paths, ["/explore", "/book/1", "/catalog", "/catalog/2", "/chapter/1", "/chapter/1/2"])
    }

    func testOriginalQQBrowserNormalizerIsExecutedBeforeItsBookListRule() async throws {
        let fixture = try XCTUnwrap(TestFixtureSupport.url(name: "qq-browser-response", extension: "js", subdirectory: "Fixtures/bodyjs"))
        let script = try String(contentsOf: fixture, encoding: .utf8)
        let source = BookSource(bookSourceName: "QQ fixture", bookSourceUrl: "https://novel.html5.qq.com",
                                searchUrl: try encodedURL("https://so.html5.qq.com/ajax/real/search_result?q={{key}}", script: script),
                                ruleSearch: SourceRule(fields: ["bookList": "$.books[*]", "name": "$.name", "author": "$.author", "bookUrl": "$.bookUrl"]))
        let network = URLBodyFixtureNetwork(responses: [
            "/ajax/real/search_result": #"{"data":{"state":[{"items":[{"docId":"90000001_1100468914","title":"Fixture","author":"Author","cover_url":"https://fixture.test/c.jpg"}]}]}}"#,
            "/wechat": #"{"booklist":[]}"#
        ])
        let books = try await LegadoSourceEngine(network: network).searchBooks(source: source, keyword: "Fixture", page: 1).get()
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.name, "Fixture")
        XCTAssertEqual(books.first?.bookUrl, "https://novel.html5.qq.com/qbread/api/novel/bookInfo?resourceId=1100468914")
        let paths = await network.paths
        XCTAssertEqual(paths, ["/ajax/real/search_result", "/wechat"])
    }

    func testTopLevelReturnBodyJSIsSupported() async throws {
        let source = BookSource(bookSourceName: "Return body", bookSourceUrl: "https://fixture.test",
                                searchUrl: try encodedURL("https://fixture.test/search", script: "return result.replace('ENCODED','Fixture');"),
                                ruleSearch: SourceRule(fields: ["bookList":"$.books[*]", "name":"$.name", "bookUrl":"$.url"]))
        let network = URLBodyFixtureNetwork(responses: ["/search": #"{"books":[{"name":"ENCODED","url":"/book/1"}]}"#])
        let books = try await LegadoSourceEngine(network: network).searchBooks(source: source, keyword: "Fixture", page: 1).get()
        XCTAssertEqual(books.first?.name, "Fixture")
    }

    func testRuntimeFailureDoesNotReplayScriptSideEffects() async throws {
        let source = BookSource(bookSourceName: "Single attempt", bookSourceUrl: "https://fixture.test",
                                searchUrl: try encodedURL("https://fixture.test/search", script: """
                                function nested() { return 'value'; }
                                java.put('attempts', Number(java.get('attempts') || 0) + 1);
                                throw new Error('do not replay');
                                """),
                                ruleSearch: SourceRule(fields: ["bookList":"$.books[*]", "name":"$.name", "bookUrl":"$.url"]))
        let engine = LegadoSourceEngine(network: URLBodyFixtureNetwork(responses: ["/search":"{}"] ))
        guard case .failure = await engine.searchBooks(source: source, keyword: "Fixture", page: 1) else {
            return XCTFail("Expected a runtime failure")
        }
        XCTAssertEqual(engine.persistentState(for: source).get("attempts"), "1")
    }

    private func encodedURL(_ url: String, script: String) throws -> String {
        url + "," + (try json(["bodyJs": script]))
    }

    private func json(_ object: Any) throws -> String {
        String(data: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]), encoding: .utf8)!
    }
}

private actor URLBodyFixtureNetwork: SourceNetworkClient {
    let responses: [String: String]
    private(set) var paths: [String] = []

    init(responses: [String: String]) { self.responses = responses }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        paths.append(request.url.path)
        guard let body = responses[request.url.path] else { return .failure(.network("Unexpected fixture path: " + request.url.path)) }
        return .success(SourceResponse(url: request.url, statusCode: 200, headers: ["Content-Type":"application/json"], body: body, data: Data(body.utf8)))
    }
}
