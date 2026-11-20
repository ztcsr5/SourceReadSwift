import Foundation
import XCTest
@testable import SourceReadSwift

/// Exercises the scripted POST/header contract in a synthetic 书山-shaped fixture.
/// This does not replay the original source's jsLib, host selection or chapter URL helpers.
final class BookShanCatalogRequestTests: XCTestCase {
    func testCatalogRuleSendsJSONPostWithDynamicHeadersAndBuildsChapters() async throws {
        let source = BookShanCatalogFixture.makeSource()
        let book = try BookShanCatalogFixture.book(source: source)
        let network = BookShanCatalogFixtureNetwork(statusCode: 200)
        let engine = BookShanCatalogFixture.makeEngine(network: network)

        let result = await engine.getChapterList(source: source, book: book)
        guard case .success(let chapters) = result else {
            return XCTFail("书山目录规则未生成章节：\(result)")
        }

        XCTAssertEqual(chapters.map(\.title), ["第一章：样例"])
        XCTAssertEqual(chapters.first?.url, "https://shushan.fixture.invalid/chapter/chapter-1")

        let requests = await network.recordedRequests()
        XCTAssertEqual(requests.count, 1, "目录规则应只发出一次 java.ajax 子请求")
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://shushan.fixture.invalid/catalog")
        XCTAssertEqual(request.method, .post)

        let contentType = request.headers.first {
            $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame
        }?.value
        XCTAssertEqual(contentType, "application/json; charset=utf-8")
        XCTAssertEqual(request.headers["X-Api-Key"], "fixture-api-key")
        XCTAssertEqual(request.headers["X-Novel-Token"], "fixture-novel-token")
        XCTAssertTrue(request.headers["User-Agent"]?.hasPrefix("Mozilla/") == true)

        let body = try XCTUnwrap(request.body)
        let catalog = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(Set(catalog.keys), Set(["source", "url", "name", "bookid", "tab"]))
        XCTAssertEqual(catalog["source"] as? String, "fixture-source")
        XCTAssertEqual(catalog["url"] as? String, "https://shushan.fixture.invalid/book/1")
        XCTAssertEqual(catalog["name"] as? String, "fixture-book")
        XCTAssertEqual(catalog["bookid"] as? String, "fixture-book-id")
        XCTAssertEqual(catalog["tab"] as? String, "novel")
    }

    func testCatalogHTTPErrorsAreReturnedWithoutRepeatingThePost() async throws {
        for status in [400, 500, 502] {
            let source = BookShanCatalogFixture.makeSource()
            let book = try BookShanCatalogFixture.book(source: source)
            let network = BookShanCatalogFixtureNetwork(statusCode: status)
            let engine = BookShanCatalogFixture.makeEngine(network: network)

            let result = await engine.getChapterList(source: source, book: book)
            guard case .failure(.network(let message)) = result else {
                return XCTFail("HTTP \(status) 子请求应保留网络错误，实际：\(result)")
            }
            XCTAssertTrue(message.contains("HTTP \(status)"), message)
            XCTAssertEqual(SourceDiagnosticClassifier.kind(error: .network(message), stage: "toc"), .network)

            let requests = await network.recordedRequests()
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests.first?.method, .post)
        }
    }

    func testScriptCanRecoverAnHTTPErrorAndReturnValidChapters() async throws {
        let source = BookShanCatalogFixture.makeSource(chapterList:
            "@js: JSON.parse(java.ajax('https://shushan.fixture.invalid/catalog')).data || [{title:'恢复章节',url:'https://shushan.fixture.invalid/chapter/recovered'}]")
        let book = try BookShanCatalogFixture.book(source: source)
        let network = BookShanCatalogFixtureNetwork(statusCode: 400)
        let engine = BookShanCatalogFixture.makeEngine(network: network)
        let chapters = try await engine.getChapterList(source: source, book: book).get()
        XCTAssertEqual(chapters.map(\.title), ["恢复章节"])

        let requests = await network.recordedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testEmptyScriptResultPreservesTransportFailureWithoutRetry() throws {
        for failure in [
            SourceEngineError.network("书源脚本的子请求超时"),
            .network("书源脚本的子请求失败，未收到可用响应")
        ] {
            let source = BookShanCatalogFixture.makeSource(chapterList:
                "@js: java.ajax('https://shushan.fixture.invalid/catalog'); []")
            let context = RuleExecutionContext(source: source)
            var attempts = 0
            context.responseHandler = { [weak context] _ in
                attempts += 1
                context?.recordScriptRequestFailure(failure)
                return .noHTTPResponse
            }
            let response = SourceResponse(url: try XCTUnwrap(URL(string: BookShanCatalogFixture.baseURL)),
                statusCode: 200, headers: [:], body: "{}", data: Data("{}".utf8))
            let result = ChapterListParser(executionContext: context).parse(
                source: source, book: try BookShanCatalogFixture.book(source: source), response: response)
            guard case .failure(let error) = result else { return XCTFail("Empty script result must fail") }
            XCTAssertEqual(error, failure)
            XCTAssertEqual(attempts, 1)
        }
    }

    func testEmptyScriptDoesNotReuseAnEarlierPagesJavaScriptError() throws {
        let source = BookShanCatalogFixture.makeSource(chapterList: "@js: []")
        let context = RuleExecutionContext(source: source)
        context.recordJavaScriptError("previous page failure")
        let response = SourceResponse(url: try XCTUnwrap(URL(string: BookShanCatalogFixture.baseURL)),
            statusCode: 200, headers: [:], body: "{}", data: Data("{}".utf8))
        let result = ChapterListParser(executionContext: context).parse(
            source: source, book: try BookShanCatalogFixture.book(source: source), response: response)
        guard case .failure(let error) = result else { return XCTFail("Empty script must not produce chapters") }
        XCTAssertFalse(error.displayMessage.contains("previous page failure"))
    }
}

private enum BookShanCatalogFixture {
    static let baseURL = "https://shushan.fixture.invalid"

    // Keep the real helper contract but replace host/key values and the
    // source-specific chapter URL encoding so no credentials or routes escape.
    static let library = """
    function getServerHost() { return 'https://shushan.fixture.invalid'; }
    function getSecretKey() { return 'fixture-api-key'; }
    function deviceType() { return false; }
    function showTabTips(_) {}
    function buildChapterUrl(chapter, catalog) {
      return 'https://shushan.fixture.invalid/chapter/' + encodeURIComponent(String(chapter.cid));
    }
    """

    static let header = """
    @js:
    JSON.stringify({
      "User-Agent": java.getWebViewUA(),
      "X-Api-Key": getSecretKey(),
      "X-Novel-Token": "fixture-novel-token"
    })
    """

    // Source rule shape: decode the typed data URL, project the catalog,
    // POST it via java.ajax, then map the returned chapter rows.
    static let chapterList = """
    <js>
    let res = JSON.parse(java.hexDecodeToString(result));
    let catalog = {source: res.source, url: res.url, name: res.name, bookid: res.bookid || "", tab: res.tab || "novel"};
    showTabTips(catalog);
    let op = {method: "POST", body: catalog};
    let catalogUrl = getServerHost() + '/catalog,' + JSON.stringify(op);
    let response = java.ajax(catalogUrl);
    let device = deviceType() ? 'ios' : 'android';
    if (device == 'android') {
      var typeMap = {audio:32, comic:64};
      book.type = catalog.tab in typeMap ? typeMap[catalog.tab] : 8;
    } else {
      var typeMap = {audio:1, comic:2, video:3};
      book.type = catalog.tab in typeMap ? typeMap[catalog.tab] : 0;
    }
    JSON.parse(response).data.map((chapter) => {
      if (chapter.isVolume == true) { chapter.url = ""; return chapter; }
      chapter.url = buildChapterUrl(chapter, catalog);
      return chapter;
    });
    </js>
    """

    static func makeSource(chapterList: String? = nil) -> BookSource {
        BookSource(
            bookSourceName: "书山聚合 fixture",
            bookSourceUrl: baseURL,
            bookSourceType: 0,
            ruleToc: SourceRule(fields: [
                "chapterList": chapterList ?? Self.chapterList,
                "chapterName": "title",
                "chapterUrl": "url"
            ]),
            header: header,
            raw: ["jsLib": library]
        )
    }

    static func book(source: BookSource) throws -> BookDetail {
        let catalog: [String: String] = [
            "source": "fixture-source",
            "url": "https://shushan.fixture.invalid/book/1",
            "name": "fixture-book",
            "bookid": "fixture-book-id",
            "tab": "novel"
        ]
        let payload = try JSONSerialization.data(withJSONObject: catalog, options: [.sortedKeys])
        let encoded = payload.base64EncodedString()
        let tocURL = "data:catalogUrl;base64,\(encoded),{\"type\":\"catalogUrl\"}"
        return BookDetail(
            name: "fixture-book",
            author: nil,
            coverUrl: nil,
            bookUrl: "https://shushan.fixture.invalid/book/1",
            tocUrl: tocURL,
            sourceName: source.bookSourceName,
            sourceUrl: source.bookSourceUrl,
            intro: nil,
            latestChapter: nil
        )
    }

    static func makeEngine(network: BookShanCatalogFixtureNetwork) -> LegadoSourceEngine {
        let engine = LegadoSourceEngine(
            network: network,
            cookieStore: SourceCookieStore(storageURL: nil),
            scriptCacheStore: SourceScriptCacheStore(isPersistent: false)
        )
        engine.allowWebViewFallback = false
        return engine
    }
}

private actor BookShanCatalogFixtureNetwork: SourceNetworkClient {
    private let statusCode: Int
    private var requests: [SourceRequest] = []

    init(statusCode: Int) {
        self.statusCode = statusCode
    }

    func recordedRequests() -> [SourceRequest] { requests }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        if request.url.scheme?.lowercased() == "data" {
            // Typed inline envelopes are decoded locally by the existing client.
            return await URLSessionSourceNetworkClient().load(request)
        }
        requests.append(request)
        guard request.url.absoluteString == "https://shushan.fixture.invalid/catalog" else {
            return .failure(.network("Unexpected fixture request"))
        }
        let body = statusCode == 200
            ? #"{"data":[{"title":"第一章：样例","cid":"chapter-1"}]}"#
            : #"{"data":null}"#
        return .success(SourceResponse(
            url: request.url,
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            body: body,
            data: Data(body.utf8)
        ))
    }
}
