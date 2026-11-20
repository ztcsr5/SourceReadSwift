import Foundation
import XCTest
@testable import SourceReadSwift

/// The original registry-backed source, with a populated normal cache and synthetic credentials.
final class SyiismOriginalPipelineTests: XCTestCase {
    func testAggregateSearchRowKeepsItsOwnSourceThroughTwoChapterBodies() async throws {
        let fixture = try loadSource()
        let network = SyiismOriginalNetwork(requiresLogin: false)
        let engine = try makeEngine(source: fixture, network: network)

        let books = try await engine.searchBooks(source: fixture, keyword: "fixture", page: 1).get()
        XCTAssertEqual(books.map(\.name), ["聚合行来源回放"])
        let book = try XCTUnwrap(books.first)
        XCTAssertEqual(URL(string: book.bookUrl)?.path, "/qq_luomu/detail")
        let detail = try await engine.getBookDetail(source: fixture, book: book).get()
        XCTAssertEqual(detail.name, book.name)
        XCTAssertTrue(detail.intro?.contains("离线来源传播夹具") == true)
        XCTAssertEqual(URL(string: try XCTUnwrap(detail.tocUrl))?.path, "/qq_luomu/chapter")

        let chapters = try await engine.getChapterList(source: fixture, book: detail).get()
        XCTAssertEqual(chapters.map(\.title), ["第一章 来源", "第二章 保真"])
        XCTAssertEqual(chapters.map(\.bookUrl), [book.bookUrl, book.bookUrl])
        guard chapters.count == SyiismOriginalRoutes.itemIDs.count else {
            return XCTFail("The original source must preserve both registered chapters")
        }
        for (index, chapter) in chapters.enumerated() {
            let components = try XCTUnwrap(URLComponents(string: chapter.url))
            XCTAssertEqual(components.path, "/qq_luomu/content")
            XCTAssertEqual(components.queryItems?.first { $0.name == "itemId" }?.value, SyiismOriginalRoutes.itemIDs[index])
            let content = try await engine.getContent(source: fixture, chapter: chapter).get()
            XCTAssertEqual(content.paragraphs, SyiismOriginalRoutes.paragraphs[index])
        }
        let requests = await network.recordedRequests()
        XCTAssertEqual(requests.map { $0.url.path }, [
            "/fq_novel/search", "/qq_luomu/detail", "/qq_luomu/chapter",
            "/qq_luomu/content", "/qq_luomu/content"
        ])
        XCTAssertTrue(requests.allSatisfy { $0.method == .get && $0.body == nil })
        let failures = await network.recordedFailures()
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "; "))
    }

    func testSearchHTTP401StopsBeforeParsingOrRequestingTheDetail() async throws {
        let source = try loadSource()
        let network = SyiismOriginalNetwork(requiresLogin: true)
        let engine = try makeEngine(source: source, network: network)
        let result = await engine.searchBooks(source: source, keyword: "fixture", page: 1)
        guard case .failure(.network(let message)) = result else {
            return XCTFail("HTTP 401 must remain a transport failure: \(result)")
        }
        XCTAssertTrue(message.contains("HTTP 401"), message)
        let requests = await network.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url.path, "/fq_novel/search")
        let failures = await network.recordedFailures()
        XCTAssertTrue(failures.isEmpty)
    }

    func testColdRegistryCandidateKeepsCustomGatewayAndAPIKeyWithoutFetchingRegistry() async throws {
        let fixtureURL = TestFixtureSupport.directory("syiism").appendingPathComponent("source.json")
        let fixtureJSON = try Data(contentsOf: fixtureURL)
        var definition = try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureJSON) as? [String: Any])
        let library = try XCTUnwrap(definition["jsLib"] as? String)
        let originalCondition = "if (d.origin && ids.indexOf(d.origin) < 0)"
        let candidateCondition = "if (ids.length && d.origin && ids.indexOf(d.origin) < 0)"
        let occurrenceCount = library.components(separatedBy: originalCondition).count - 1
        XCTAssertEqual(occurrenceCount, 1)
        guard occurrenceCount == 1 else { return }
        definition["jsLib"] = library.replacingOccurrences(of: originalCondition, with: candidateCondition)
        let candidateJSON = try JSONSerialization.data(withJSONObject: definition)
        let candidate = try JSONDecoder().decode(BookSource.self, from: candidateJSON)

        let cache = SourceScriptCacheStore(isPersistent: false)
        let network = SyiismOriginalNetwork(requiresLogin: false)
        let engine = LegadoSourceEngine(network: network, cookieStore: SourceCookieStore(storageURL: nil), scriptCacheStore: cache)
        engine.allowWebViewFallback = false
        let configuration: [String: Any] = [
            "host": SyiismOriginalRoutes.origin, "origin": "fq_novel", "origin_zh": "番茄小说",
            "category": "fq", "tab_type": "3", "tone_id": "0", "module": "小说",
            "apikey": "fixture-api-key", "agg_search": "0", "showPara": false, "showChap": false,
            "syncBubble": 0, "introBeautify": false
        ]
        let configurationJSON = try JSONSerialization.data(withJSONObject: configuration)
        let state = engine.persistentState(for: candidate)
        state.put(String(decoding: configurationJSON, as: UTF8.self), for: "source.variable")
        XCTAssertNil(try cache.get("syiism_origins", scope: candidate.bookSourceUrl))

        let books = try await engine.searchBooks(source: candidate, keyword: "fixture", page: 1).get()
        XCTAssertEqual(books.map(\.name), ["聚合行来源回放"])
        let requests = await network.recordedRequests()
        XCTAssertEqual(requests.map { $0.url.path }, ["/fq_novel/search"])
        XCTAssertEqual(requests.first?.url.host, "syiism.fixture.invalid")
        let failures = await network.recordedFailures()
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "; "))
        XCTAssertNil(try cache.get("syiism_origins", scope: candidate.bookSourceUrl))

        let storedJSON = Data(state.get("source.variable").utf8)
        let storedConfiguration = try XCTUnwrap(JSONSerialization.jsonObject(with: storedJSON) as? [String: Any])
        XCTAssertEqual(storedConfiguration["host"] as? String, SyiismOriginalRoutes.origin)
        XCTAssertEqual(storedConfiguration["origin"] as? String, "fq_novel")
        XCTAssertEqual(storedConfiguration["apikey"] as? String, "fixture-api-key")
    }

    private func loadSource() throws -> BookSource {
        let fixtureURL = TestFixtureSupport.directory("syiism").appendingPathComponent("source.json")
        return try JSONDecoder().decode(BookSource.self, from: Data(contentsOf: fixtureURL))
    }

    private func makeEngine(source: BookSource, network: SyiismOriginalNetwork) throws -> LegadoSourceEngine {
        let cache = SourceScriptCacheStore(isPersistent: false)
        // The original LP_INIT resets a custom host when its selected origin is absent.
        // This fixture covers an existing registry cache, not that cold-cache source defect.
        let registry: [String: Any] = ["t": Date().timeIntervalSince1970 * 1_000, "list": [
            ["id": "fq_novel", "name": "番茄小说", "category": "fq", "media": "text"],
            ["id": "qq_luomu", "name": "QQ阅读", "category": "qq", "media": "text"]
        ]]
        let registryJSON = try JSONSerialization.data(withJSONObject: registry)
        try cache.put(String(decoding: registryJSON, as: UTF8.self), for: "syiism_origins", scope: source.bookSourceUrl)
        let engine = LegadoSourceEngine(network: network, cookieStore: SourceCookieStore(storageURL: nil), scriptCacheStore: cache)
        engine.allowWebViewFallback = false
        let configuration: [String: Any] = [
            "host": SyiismOriginalRoutes.origin, "origin": "fq_novel", "origin_zh": "番茄小说",
            "category": "fq", "tab_type": "3", "tone_id": "0", "module": "小说",
            "apikey": "fixture-api-key", "agg_search": "0", "showPara": false, "showChap": false,
            "syncBubble": 0, "introBeautify": false
        ]
        let configurationJSON = try JSONSerialization.data(withJSONObject: configuration)
        engine.persistentState(for: source).put(String(decoding: configurationJSON, as: UTF8.self), for: "source.variable")
        return engine
    }
}

private enum SyiismOriginalRoutes {
    static let origin = "https://syiism.fixture.invalid"
    static let bookID = "syiism-book-fixture"
    static let itemIDs = ["syiism-item-1", "syiism-item-2"]
    static let paragraphs = [["第一章的来源标识必须保持原样。", "这一段只属于第一章。"],
        ["第二章的来源标识同样来自搜索行。", "这一段只属于第二章。"]]
}

private actor SyiismOriginalNetwork: SourceNetworkClient {
    private let requiresLogin: Bool
    private var requests: [SourceRequest] = []
    private var visited: Set<String> = []
    private var failures: [String] = []

    init(requiresLogin: Bool) { self.requiresLogin = requiresLogin }
    func recordedRequests() -> [SourceRequest] { requests }
    func recordedFailures() -> [String] { failures }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        requests.append(request)
        guard request.url.scheme == "https", request.url.host == "syiism.fixture.invalid",
              request.url.port == nil, request.url.user == nil, request.url.password == nil,
              request.method == .get, request.body == nil, visited.insert(request.url.absoluteString).inserted else {
            return reject("Unexpected origin, method, body or repeated Syiism request")
        }
        do {
            let payload = try payload(for: request)
            let bytes = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            let status = requiresLogin ? 401 : 200
            return .success(SourceResponse(url: request.url, statusCode: status,
                headers: ["Content-Type": "application/json"], body: String(decoding: bytes, as: UTF8.self), data: bytes))
        } catch {
            return reject("Unexpected Syiism route or complete query at \(request.url.path)")
        }
    }

    private func payload(for request: SourceRequest) throws -> [String: Any] {
        let routes = SyiismOriginalRoutes.self
        let components = try XCTUnwrap(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        let query = items.reduce(into: [String: String]()) { $0[$1.name] = $1.value ?? "" }
        var expected = ["api_key": "fixture-api-key"]
        let payload: [String: Any]
        switch request.url.path {
        case "/fq_novel/search":
            expected.merge(["query": "fixture", "page": "1"]) { _, new in new }
            payload = requiresLogin ? ["code": 401, "msg": "Fixture login required"] : ["bookList": [[
                "bookId": routes.bookID, "source": "qq_luomu", "name": "聚合行来源回放",
                "author": "夹具作者", "intro": "离线来源传播夹具"
            ]]]
        case "/qq_luomu/detail":
            expected.merge(["bookId": routes.bookID, "tabType": "3"]) { _, new in new }
            payload = ["bookId": routes.bookID, "name": "聚合行来源回放", "author": "夹具作者",
                "intro": "离线来源传播夹具", "bookType": "text", "bookTypeCode": 8]
        case "/qq_luomu/chapter":
            expected.merge(["bookId": routes.bookID, "tabType": "3"]) { _, new in new }
            payload = ["chapterList": routes.itemIDs.enumerated().map { index, identifier in
                ["itemId": identifier, "title": index == 0 ? "第一章 来源" : "第二章 保真"]
            }]
        case "/qq_luomu/content":
            let index = try XCTUnwrap(routes.itemIDs.firstIndex(of: query["itemId"] ?? ""))
            expected.merge(["bookId": routes.bookID, "tabType": "3", "toneId": "0",
                "itemId": routes.itemIDs[index]]) { _, new in new }
            payload = ["contentType": "text", "data": ["content": routes.paragraphs[index].joined(separator: "\n")]]
        default:
            throw SourceEngineError.rule("Unregistered Syiism route")
        }
        guard query == expected, items.count == expected.count else {
            throw SourceEngineError.rule("Syiism query did not preserve the selected row")
        }
        return payload
    }

    private func reject(_ message: String) -> Result<SourceResponse, SourceEngineError> {
        failures.append(message)
        return .failure(.network(message))
    }
}
