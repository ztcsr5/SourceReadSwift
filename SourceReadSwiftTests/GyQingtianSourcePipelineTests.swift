import Foundation
import XCTest
@testable import SourceReadSwift

/// Keeps the original libraries and four-stage rules; all server replies are authored offline.
final class GyQingtianSourcePipelineTests: XCTestCase {
    func testOriginalGuangyuRulesKeepCarriersAndTwoChapterIdentities() async throws {
        try await replayFixture(named: "guangyu")
    }

    func testOriginalDahuilangRulesKeepObjectBodiesAndTwoChapterIdentities() async throws {
        try await replayFixture(named: "dahuilang")
    }

    private func replayFixture(named name: String) async throws {
        let fixture = try GyQingtianPipelineFixture.load(named: name)
        let network = GyQingtianPipelineNetwork(origin: fixture.origin, routes: fixture.routes)
        let engine = LegadoSourceEngine(
            network: network,
            cookieStore: SourceCookieStore(storageURL: nil),
            scriptCacheStore: SourceScriptCacheStore(isPersistent: false)
        )
        engine.allowWebViewFallback = false
        engine.persistentState(for: fixture.source).put(fixture.configurationJSON, for: "source.variable")

        let books = try assertStage(await engine.searchBooks(source: fixture.source, keyword: "fixture", page: 2), stage: "search")
        XCTAssertEqual(books.count, 1)
        let book = try XCTUnwrap(books.first)
        XCTAssertEqual(book.name, fixture.expected.name)
        XCTAssertEqual(book.author, fixture.expected.author)
        try assertEnvelope(book.bookUrl, expected: fixture.expected.detail)

        let detail = try assertStage(await engine.getBookDetail(source: fixture.source, book: book), stage: "detail")
        XCTAssertEqual(detail.name, fixture.expected.name)
        XCTAssertEqual(detail.author, fixture.expected.author)
        let catalogURL = try XCTUnwrap(detail.tocUrl)
        try assertEnvelope(catalogURL, expected: fixture.expected.catalog)

        let chapters = try assertStage(await engine.getChapterList(source: fixture.source, book: detail), stage: "catalog")
        XCTAssertEqual(chapters.map(\.title), fixture.expected.chapterTitles)
        XCTAssertEqual(chapters.map(\.index), [0, 1])
        XCTAssertEqual(chapters.map(\.bookUrl), Array(repeating: book.bookUrl, count: 2))
        guard chapters.count == 2, fixture.expected.contents.count == 2, fixture.expected.paragraphs.count == 2 else {
            return XCTFail("The original catalog must yield two independent fixture chapters")
        }
        XCTAssertNotEqual(chapters[0].url, chapters[1].url)
        for (index, chapter) in chapters.enumerated() {
            try assertEnvelope(chapter.url, expected: fixture.expected.contents[index])
            let content = try assertStage(await engine.getContent(source: fixture.source, chapter: chapter), stage: "content \(index)")
            XCTAssertEqual(content.paragraphs, fixture.expected.paragraphs[index])
        }

        let snapshot = await network.snapshot()
        XCTAssertEqual(snapshot.requests.count, fixture.routes.count)
        XCTAssertEqual(snapshot.consumedRoutes, fixture.routes.count)
        XCTAssertEqual(snapshot.requests.map { $0.url.path }, fixture.routes.map(\.path))
        XCTAssertEqual(snapshot.inlineCount, fixture.expected.inlineCount)
        XCTAssertTrue(snapshot.failures.isEmpty, snapshot.failures.joined(separator: "; "))
        for request in snapshot.requests {
            if request.method == .get {
                XCTAssertNil(request.body, "Native request building must remove a GET descriptor's empty body")
            } else {
                let contentType = request.headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
                XCTAssertTrue(contentType?.lowercased().hasPrefix("application/json") == true)
            }
        }
    }

    private func assertStage<Value>(_ result: Result<Value, SourceEngineError>, stage: String) throws -> Value {
        if case .failure(let failure) = result {
            XCTFail("Original Gy/Qingtian \(stage) failed: \(failure)")
        }
        return try result.get()
    }

    private func assertEnvelope(_ address: String, expected: GyQingtianPipelineFixture.Envelope) throws {
        let directive = SourceURLDirectiveParser().parse(address)
        XCTAssertEqual(directive.responseType, expected.type)
        let url = try XCTUnwrap(URL(string: directive.urlText))
        let response = try SourceInlineEnvelope.response(for: url).get()
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: response.data) as? NSDictionary)
        XCTAssertTrue(payload.isEqual(NSDictionary(dictionary: expected.payload)), "Unexpected \(expected.type) carrier payload")
    }
}

private struct GyQingtianPipelineFixture: Decodable {
    struct Envelope: Decodable {
        let type: String
        let payload: [String: String]
    }

    struct Expected: Decodable {
        let name: String
        let author: String
        let chapterTitles: [String]
        let paragraphs: [[String]]
        let inlineCount: Int
        let detail: Envelope
        let catalog: Envelope
        let contents: [Envelope]
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
    let configurationJSON: String
    let origin: String
    let routes: [Route]
    let expected: Expected

    static func load(named name: String) throws -> Self {
        let url = TestFixtureSupport.directory("gy-qingtian").appendingPathComponent("\(name)-pipeline.json")
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

private actor GyQingtianPipelineNetwork: SourceNetworkClient {
    struct Snapshot: Sendable {
        let requests: [SourceRequest]
        let consumedRoutes: Int
        let inlineCount: Int
        let failures: [String]
    }

    private let origin: String
    private let routes: [GyQingtianPipelineFixture.Route]
    private var consumedRoutes: Set<Int> = []
    private var requests: [SourceRequest] = []
    private var inlineCount = 0
    private var failures: [String] = []

    init(origin: String, routes: [GyQingtianPipelineFixture.Route]) {
        self.origin = origin
        self.routes = routes
    }

    func snapshot() -> Snapshot {
        Snapshot(requests: requests, consumedRoutes: consumedRoutes.count, inlineCount: inlineCount, failures: failures)
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        if request.url.scheme?.lowercased() == "data" {
            inlineCount += 1
            guard request.shouldReturnInlineHex else {
                failures.append("Typed inline request lost the native hex flag")
                return .failure(.rule("Gy/Qingtian typed envelope must use the native hex response"))
            }
            return SourceInlineEnvelope.response(for: request.url, asHex: request.shouldReturnInlineHex)
        }

        requests.append(request)
        guard let routeIndex = routes.indices.first(where: {
            !consumedRoutes.contains($0) && matches(request, route: routes[$0])
        }) else {
            failures.append("Unexpected, duplicate or mismatched fixture request: \(request.method.rawValue) \(request.url.path)")
            return .failure(.network("Request did not match an unused offline Gy/Qingtian route"))
        }
        consumedRoutes.insert(routeIndex)
        let response = routes[routeIndex].response
        return .success(SourceResponse(
            url: request.url, statusCode: response.statusCode,
            headers: ["Content-Type": response.contentType],
            body: response.body, data: Data(response.body.utf8)
        ))
    }

    private func matches(_ request: SourceRequest, route: GyQingtianPipelineFixture.Route) -> Bool {
        guard let expectedOrigin = URLComponents(string: origin),
              let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false),
              components.scheme == expectedOrigin.scheme, components.host == expectedOrigin.host,
              components.port == expectedOrigin.port, components.user == nil, components.password == nil,
              components.fragment == nil, components.path == route.path, request.method.rawValue == route.method else { return false }
        let queryItems = components.queryItems ?? []
        guard queryItems.count == route.query.count, Set(queryItems.map(\.name)).count == queryItems.count,
              queryItems.allSatisfy({ route.query[$0.name] == ($0.value ?? "") }) else { return false }
        guard let expectedBody = route.body else { return request.body == nil }
        guard let requestBody = request.body,
              let actual = (try? JSONSerialization.jsonObject(with: requestBody)) as? NSDictionary,
              let expected = (try? JSONSerialization.jsonObject(with: Data(expectedBody.utf8))) as? NSDictionary else { return false }
        return actual.isEqual(expected)
    }
}
