import Foundation
import XCTest
@testable import SourceReadSwift

/// Replays index 8's unmodified rules and original helper functions against local responses.
/// The fixture deliberately omits the first ID candidates to exercise the real fallback chains.
final class PyFQGoSourcePipelineTests: XCTestCase {
    func testOriginalNovelRulesRunSearchDetailTOCAndContent() async throws {
        try await replayPipeline(primaryHealthFails: false)
    }

    func testOriginalHostSelectionFallsBackOnceBeforeTheSamePipeline() async throws {
        try await replayPipeline(primaryHealthFails: true)
    }

    private func replayPipeline(primaryHealthFails: Bool) async throws {
        let sourceURL = TestFixtureSupport.directory("pyfq-go").appendingPathComponent("source.json")
        let source = try JSONDecoder().decode(BookSource.self, from: Data(contentsOf: sourceURL))
        XCTAssertEqual(source.bookSourceName, "番茄🍅（沐凡·PyFQ-Go本地）")
        let network = PyFQGoFixtureNetwork(primaryHealthFails: primaryHealthFails)
        let engine = LegadoSourceEngine(
            network: network,
            cookieStore: SourceCookieStore(storageURL: nil),
            scriptCacheStore: SourceScriptCacheStore(isPersistent: false)
        )
        engine.allowWebViewFallback = false
        let hosts = primaryHealthFails
            ? [PyFQGoFixtureRoutes.unavailableHost, PyFQGoFixtureRoutes.host]
            : [PyFQGoFixtureRoutes.host]
        let configuration: [String: Any] = [
            "hosts": hosts, "server": "", "server_id": 0,
            "api_key": "fixture-api-key", "module": 3, "type": "小说模式",
            "commentDefaultsVersion": 2, "showPara": false, "showChap": false,
            "showAuthor": false, "showBook": false, "richToc": false,
            "txtDownload": false, "richIntro": true
        ]
        let configurationJSON = try JSONSerialization.data(withJSONObject: configuration, options: [.sortedKeys])
        engine.persistentState(for: source).put(String(decoding: configurationJSON, as: UTF8.self), for: "source.variable")

        let books = try await engine.searchBooks(source: source, keyword: "系统", page: 1).get()
        XCTAssertEqual(books.map(\.name), ["聚合规则回放"])
        let book = try XCTUnwrap(books.first)
        XCTAssertEqual(book.author, "夹具作者")
        XCTAssertEqual(book.bookUrl, PyFQGoFixtureRoutes.detail)

        let detail = try await engine.getBookDetail(source: source, book: book).get()
        XCTAssertEqual(detail.name, "聚合规则回放")
        XCTAssertEqual(detail.author, "夹具作者")
        XCTAssertEqual(detail.tocUrl, PyFQGoFixtureRoutes.directory)
        XCTAssertTrue(detail.intro?.contains("离线正文链路夹具") == true)

        let chapters = try await engine.getChapterList(source: source, book: detail).get()
        XCTAssertEqual(chapters.map(\.title), ["第一章 规则回放"])
        let chapter = try XCTUnwrap(chapters.first)
        XCTAssertEqual(chapter.url, PyFQGoFixtureRoutes.ping)
        XCTAssertEqual(chapter.bookUrl, PyFQGoFixtureRoutes.detail)

        let content = try await engine.getContent(source: source, chapter: chapter).get()
        XCTAssertEqual(content.paragraphs, ["这是用于验证解析的第一段。", "第二段保持原来的顺序。"])

        let requests = await network.recordedRequests()
        let unavailableHealth = primaryHealthFails ? [PyFQGoFixtureRoutes.unavailableHealth] : []
        XCTAssertEqual(requests.map { $0.url.absoluteString }, unavailableHealth + [
            PyFQGoFixtureRoutes.health, PyFQGoFixtureRoutes.search, PyFQGoFixtureRoutes.detail,
            PyFQGoFixtureRoutes.directory, PyFQGoFixtureRoutes.ping,
            PyFQGoFixtureRoutes.content, PyFQGoFixtureRoutes.footer
        ])
        XCTAssertTrue(requests.allSatisfy { $0.method == .get && $0.body == nil })
        XCTAssertTrue(requests.allSatisfy { $0.url.host?.hasSuffix(".fixture.invalid") == true })
    }
}

private enum PyFQGoFixtureRoutes {
    static let host = "https://pyfq.fixture.invalid"
    static let unavailableHost = "https://unavailable-pyfq.fixture.invalid"
    static let bookID = "7357061000123456789"
    static let chapterID = "7367061000123456789"
    static let key = "api_key=fixture-api-key"
    static let health = "\(host)/api/health?\(key)"
    static let unavailableHealth = "\(unavailableHost)/api/health?\(key)"
    static let search = "\(host)/api/search?query=%E7%B3%BB%E7%BB%9F&offset=0&count=10&tab_type=3&\(key)"
    static let detail = "\(host)/api/detail?book_id=\(bookID)&ys_module=3&\(key)"
    static let directory = "\(host)/api/directory?book_id=\(bookID)&ys_module=3&\(key)"
    static let ping = "\(host)/api/ping?q=\(chapterID)&book_id=\(bookID)&ys_module=3&\(key)"
    static let content = "\(host)/api/content?item_id=\(chapterID)&\(key)"
    static let footer = "\(host)/api/content_footer?module=3&\(key)"
}

private actor PyFQGoFixtureNetwork: SourceNetworkClient {
    private let primaryHealthFails: Bool
    private var requests: [SourceRequest] = []

    init(primaryHealthFails: Bool) {
        self.primaryHealthFails = primaryHealthFails
    }

    func recordedRequests() -> [SourceRequest] { requests }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        requests.append(request)
        let payload: (statusCode: Int, body: String)
        switch request.url.absoluteString {
        case PyFQGoFixtureRoutes.unavailableHealth where primaryHealthFails:
            payload = (503, #"{"code":503,"msg":"fixture unavailable"}"#)
        case PyFQGoFixtureRoutes.health:
            payload = (200, #"{"code":0}"#)
        case PyFQGoFixtureRoutes.search:
            payload = (200, #"{"code":0,"data":[{"book_data":[{"book_id_str":"7357061000123456789","book_name":"聚合规则回放","author":"夹具作者","abstract":"离线正文链路夹具"}]}]}"#)
        case PyFQGoFixtureRoutes.detail:
            payload = (200, #"{"code":0,"data":{"series_id_str":"7357061000123456789","book_name":"聚合规则回放","author":"夹具作者","abstract":"离线正文链路夹具"}}"#)
        case PyFQGoFixtureRoutes.directory:
            payload = (200, #"{"code":0,"data":{"item_data_list":[{"item_id":"7367061000123456789","title":"第一章 规则回放"}]}}"#)
        case PyFQGoFixtureRoutes.ping:
            payload = (200, #"{"code":0}"#)
        case PyFQGoFixtureRoutes.content:
            payload = (200, #"{"code":0,"data":{"content":"<p>这是用于验证解析的第一段。</p><p>第二段保持原来的顺序。</p>"}}"#)
        case PyFQGoFixtureRoutes.footer:
            payload = (200, #"{"code":0,"data":{"content":""}}"#)
        default:
            return .failure(.network("Unexpected request outside the PyFQ-Go fixture routes"))
        }
        return .success(SourceResponse(
            url: request.url, statusCode: payload.statusCode, headers: ["Content-Type": "application/json"],
            body: payload.body, data: Data(payload.body.utf8)
        ))
    }
}
