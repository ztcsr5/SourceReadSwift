import Foundation
import XCTest
@testable import SourceReadSwift

/// Original rules with documented cipher-literal redactions; all replies are authored offline.
final class TingxueOriginalPipelineTests: XCTestCase {
    func testOriginalRulesKeepSearchRowAndTwoChapterIdentitiesThroughPlaintextContent() async throws {
        let fixture = try TingxuePipelineFixture.load()
        let network = TingxuePipelineNetwork(fixture: fixture)
        let engine = makeEngine(fixture: fixture, network: network)

        let books = try await engine.searchBooks(source: fixture.source, keyword: "fixture", page: 2).get()
        XCTAssertEqual(books.count, 1)
        let book = try XCTUnwrap(books.first)
        XCTAssertEqual(book.name, fixture.expected.name)
        XCTAssertEqual(book.author, fixture.expected.author)
        try assertCarrier(book.bookUrl, stage: "detailsUrl", expected: fixture.expected.detail)

        let detail = try await engine.getBookDetail(source: fixture.source, book: book).get()
        XCTAssertEqual(detail.name, fixture.expected.name)
        XCTAssertEqual(detail.author, fixture.expected.author)
        try assertCarrier(try XCTUnwrap(detail.tocUrl), stage: "catalogUrl", expected: fixture.expected.catalog)

        let chapters = try await engine.getChapterList(source: fixture.source, book: detail).get()
        XCTAssertEqual(chapters.map(\.title), fixture.expected.chapterTitles)
        XCTAssertEqual(chapters.map(\.index), [0, 1])
        XCTAssertEqual(chapters.map(\.bookUrl), Array(repeating: book.bookUrl, count: 2))
        guard chapters.count == 2, fixture.expected.contents.count == 2, fixture.expected.paragraphs.count == 2 else {
            return XCTFail("The original catalog must preserve both independent chapters")
        }
        XCTAssertNotEqual(chapters[0].url, chapters[1].url)
        for (index, chapter) in chapters.enumerated() {
            try assertCarrier(chapter.url, stage: "contentUrl", expected: fixture.expected.contents[index])
            let content = try await engine.getContent(source: fixture.source, chapter: chapter).get()
            XCTAssertEqual(content.paragraphs, fixture.expected.paragraphs[index])
            try assertNonAudioSubContentIsEmpty(fixture: fixture, book: detail, chapterURL: chapter.url)
        }

        let snapshot = await network.snapshot()
        XCTAssertEqual(snapshot.requests.map { $0.url.path }, fixture.routes.map(\.path))
        XCTAssertEqual(snapshot.consumedRoutes, fixture.routes.count)
        XCTAssertEqual(snapshot.inlineCount, fixture.expected.inlineCount)
        XCTAssertTrue(snapshot.failures.isEmpty, snapshot.failures.joined(separator: "; "))
        for request in snapshot.requests {
            XCTAssertFalse(request.webView)
            XCTAssertEqual(header("x-novel-token", in: request), fixture.loginHeader)
            XCTAssertEqual(header("x-novel-version", in: request), "10")
            XCTAssertFalse((header("User-Agent", in: request) ?? "").isEmpty)
            XCTAssertFalse((header("x-novel-deviceid", in: request) ?? "").isEmpty)
            XCTAssertNotNil(Int(header("x-novel-timestamap", in: request) ?? ""))
            let signature = try XCTUnwrap(header("x-novel-public", in: request))
            XCTAssertNotNil(signature.range(of: #"^[0-9a-f]{32}$"#, options: .regularExpression))
            // Read requests have no body; authored MIME headers win over the JSON default.
            let expectedContentType: String? = request.method == .get ? nil
                : (["/api/catalog", "/api/content"].contains(request.url.path)
                    ? "application/json" : "application/json; charset=utf-8")
            XCTAssertEqual(header("Content-Type", in: request), expectedContentType,
                           "\(request.method.rawValue) \(request.url.path)")
        }
        let storedConfiguration = engine.persistentState(for: fixture.source).get("source.variable")
        let configurations = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(storedConfiguration.utf8)) as? [[String: Any]])
        XCTAssertEqual(configurations.count, 1, "Original ensureConfig must save its normal array representation")
        XCTAssertEqual(configurations.first?["gender"] as? String, "boy")
        XCTAssertEqual(configurations.first?["host"] as? String, fixture.origin)
    }

    func testSearchHTTP401StopsBeforeAnyInlineOrDetailRequest() async throws {
        let fixture = try TingxuePipelineFixture.load()
        let network = TingxuePipelineNetwork(fixture: fixture, rejectsSearchLogin: true)
        let engine = makeEngine(fixture: fixture, network: network)
        let result = await engine.searchBooks(source: fixture.source, keyword: "fixture", page: 2)
        guard case .failure(.network(let message)) = result else {
            return XCTFail("Search HTTP 401 must stay a transport failure")
        }
        XCTAssertEqual(message, "HTTP 401")
        let snapshot = await network.snapshot()
        XCTAssertEqual(snapshot.requests.map { $0.url.path }, ["/api/search"])
        XCTAssertEqual(snapshot.consumedRoutes, 1)
        XCTAssertEqual(snapshot.inlineCount, 0)
        XCTAssertTrue(snapshot.failures.isEmpty)
    }

    private func makeEngine(fixture: TingxuePipelineFixture, network: TingxuePipelineNetwork) -> LegadoSourceEngine {
        let engine = LegadoSourceEngine(
            network: network, cookieStore: SourceCookieStore(storageURL: nil),
            scriptCacheStore: SourceScriptCacheStore(isPersistent: false)
        )
        engine.allowWebViewFallback = false
        let state = engine.persistentState(for: fixture.source)
        state.put(fixture.configurationJSON, for: "source.variable")
        state.put(fixture.loginHeader, for: "source.loginHeader")
        return engine
    }

    private func assertCarrier(_ address: String, stage: String, expected: TingxuePipelineFixture.Carrier) throws {
        let directive = SourceURLDirectiveParser().parse(address)
        XCTAssertEqual(directive.responseType, "qingci")
        XCTAssertTrue(directive.urlText.hasPrefix("data:\(stage);base64,"))
        let url = try XCTUnwrap(URL(string: directive.urlText))
        let response = try SourceInlineEnvelope.response(for: url).get()
        let actual = try JSONSerialization.jsonObject(with: response.data)
        let expectedObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(expected))
        // Canonical JSON keeps numeric 0/1 distinct from strings and booleans.
        XCTAssertEqual(
            try JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys]),
            try JSONSerialization.data(withJSONObject: expectedObject, options: [.sortedKeys])
        )
    }

    private func assertNonAudioSubContentIsEmpty(fixture: TingxuePipelineFixture, book: BookDetail, chapterURL: String) throws {
        let rawRule = try XCTUnwrap(fixture.source.ruleContent?.fields["subContent"])
        XCTAssertTrue(rawRule.hasPrefix("@js:"))
        let directive = SourceURLDirectiveParser().parse(chapterURL)
        let url = try XCTUnwrap(URL(string: directive.urlText))
        let response = try SourceInlineEnvelope.response(for: url, asHex: true).get()
        let state = RulePersistentState(initialValues: [
            "source.variable": fixture.configurationJSON, "source.loginHeader": fixture.loginHeader
        ])
        let context = RuleExecutionContext(persistentState: state, source: fixture.source)
        let runtime = JSCoreRuntime(ajaxHandler: { _ in
            XCTFail("The original non-audio subContent branch must never request lyrics")
            return ""
        }, executionContext: context, scriptCacheStore: SourceScriptCacheStore(isPersistent: false))
        let lyrics = try runtime.evaluate(String(rawRule.dropFirst(4)), variables: [
            "source": fixture.source, "book": book, "result": response.body, "baseUrl": chapterURL
        ]).get()
        XCTAssertEqual(lyrics, "")
    }

    private func header(_ name: String, in request: SourceRequest) -> String? {
        request.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

private struct TingxuePipelineFixture: Decodable {
    struct Carrier: Codable {
        let source: String
        let sing: String
        let bookID: String
        let title: String?
        let tab: String?
        let itemID: String?
        let contentMD5: String?
        let chapterIndex: Int?

        enum CodingKeys: String, CodingKey {
            case source, sing, title, tab
            case bookID = "book_id", itemID = "item_id", contentMD5 = "content_md5", chapterIndex = "chapter_index"
        }
    }

    struct Expected: Decodable {
        let name: String
        let author: String
        let chapterTitles: [String]
        let paragraphs: [[String]]
        let inlineCount: Int
        let detail: Carrier
        let catalog: Carrier
        let contents: [Carrier]
    }

    struct Route: Decodable, Sendable {
        struct Response: Decodable, Sendable {
            let statusCode: Int
            let contentType: String
            let body: String
        }
        let method: String
        let path: String
        let query: [String: String]
        let body: String?
        let response: Response
    }

    let source: BookSource
    let origin: String
    let configurationJSON: String
    let loginHeader: String
    let routes: [Route]
    let expected: Expected

    static func load() throws -> Self {
        let url = TestFixtureSupport.directory("tingxue").appendingPathComponent("pipeline.json")
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

/// An exact, single-use route table with no fallback transport.
private actor TingxuePipelineNetwork: SourceNetworkClient {
    struct Snapshot: Sendable {
        let requests: [SourceRequest]
        let consumedRoutes: Int
        let inlineCount: Int
        let failures: [String]
    }

    private let origin: String
    private let routes: [TingxuePipelineFixture.Route]
    private let rejectsSearchLogin: Bool
    private var requests: [SourceRequest] = []
    private var consumedRoutes: Set<Int> = []
    private var inlineCount = 0
    private var failures: [String] = []

    init(fixture: TingxuePipelineFixture, rejectsSearchLogin: Bool = false) {
        origin = fixture.origin
        routes = fixture.routes
        self.rejectsSearchLogin = rejectsSearchLogin
    }

    func snapshot() -> Snapshot {
        Snapshot(requests: requests, consumedRoutes: consumedRoutes.count, inlineCount: inlineCount, failures: failures)
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        if request.url.scheme?.lowercased() == "data" {
            inlineCount += 1
            guard request.shouldReturnInlineHex else { return reject("Typed Tingxue carrier lost its native hex flag") }
            return SourceInlineEnvelope.response(for: request.url, asHex: request.shouldReturnInlineHex)
        }
        requests.append(request)
        guard let routeIndex = routes.indices.first(where: {
            !consumedRoutes.contains($0) && matches(request, route: routes[$0])
        }) else { return reject("Unexpected, repeated or mismatched offline Tingxue request") }
        consumedRoutes.insert(routeIndex)
        let response = routes[routeIndex].response
        let isUnauthorized = rejectsSearchLogin && routeIndex == 0
        let body = isUnauthorized ? #"{"code":401,"msg":"Fixture login required"}"# : response.body
        return .success(SourceResponse(
            url: request.url, statusCode: isUnauthorized ? 401 : response.statusCode,
            headers: ["Content-Type": response.contentType], body: body, data: Data(body.utf8)
        ))
    }

    private func matches(_ request: SourceRequest, route: TingxuePipelineFixture.Route) -> Bool {
        guard let expectedOrigin = URLComponents(string: origin),
              let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false),
              components.scheme == expectedOrigin.scheme, components.host == expectedOrigin.host,
              components.port == expectedOrigin.port, components.user == nil, components.password == nil,
              components.fragment == nil, components.path == route.path,
              request.method.rawValue == route.method else { return false }
        let queryItems = components.queryItems ?? []
        guard queryItems.count == route.query.count, Set(queryItems.map(\.name)).count == queryItems.count,
              queryItems.allSatisfy({ route.query[$0.name] == ($0.value ?? "") }) else { return false }
        guard let expectedBody = route.body else { return request.body == nil }
        guard let actualBody = request.body,
              let actual = try? JSONSerialization.jsonObject(with: actualBody),
              let expected = try? JSONSerialization.jsonObject(with: Data(expectedBody.utf8)),
              let actualJSON = try? JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys]),
              let expectedJSON = try? JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys]) else { return false }
        return actualJSON == expectedJSON
    }

    private func reject(_ message: String) -> Result<SourceResponse, SourceEngineError> {
        failures.append(message)
        return .failure(.network(message))
    }
}
