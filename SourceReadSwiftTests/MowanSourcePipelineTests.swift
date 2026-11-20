import Foundation
import XCTest
@testable import SourceReadSwift

/// Replays the original field rules and retained helpers against authored, offline responses.
final class MowanSourcePipelineTests: XCTestCase {
    func testOriginalRulesKeepTypedEnvelopesAndHeadersThroughTwoChapterBodies() async throws {
        var stage = "fixture decoding"
        do {
            let fixture = try MowanPipelineFixture.load()
            let network = MowanPipelineNetwork(responses: fixture.responses)
            stage = "engine setup"
            let engine = try await makeEngine(network: network)

            stage = "search"
            let books = try await engine.searchBooks(source: fixture.source, keyword: "fixture", page: 1).get()
            XCTAssertEqual(books.map(\.name), ["魔丸合成样本"])
            let book = try XCTUnwrap(books.first)
            XCTAssertEqual(book.author, "Fixture Author")
            XCTAssertEqual(book.bookUrl, inlineAddress("/api/book/detail?source=fixture-novel&book_id=book-fixture-1"))

            stage = "detail"
            let detail = try await engine.getBookDetail(source: fixture.source, book: book).get()
            XCTAssertEqual(detail.name, "魔丸合成样本·详情")
            XCTAssertEqual(detail.author, "Fixture Detail Author")
            XCTAssertTrue(detail.intro?.contains("离线合成详情") == true)
            XCTAssertEqual(detail.tocUrl, inlineAddress(MowanPipelineFixture.catalogPath))

            stage = "catalog"
            let chapters = try await engine.getChapterList(source: fixture.source, book: detail).get()
            XCTAssertEqual(chapters.map(\.title), ["第一章·合成起点", "第二章·合成终点"])
            XCTAssertEqual(chapters.map(\.url), MowanPipelineFixture.contentPaths.map(inlineAddress))
            XCTAssertEqual(chapters.map(\.bookUrl), Array(repeating: book.bookUrl, count: 2))
            guard chapters.count == fixture.expectedParagraphs.count else {
                return XCTFail("Original catalog must produce both independent fixture chapters")
            }
            for (index, chapter) in chapters.enumerated() {
                stage = "content chapter \(index + 1)"
                let content = try await engine.getContent(source: fixture.source, chapter: chapter).get()
                XCTAssertEqual(content.paragraphs, fixture.expectedParagraphs[index])
            }

            let requests = await network.recordedRequests()
            XCTAssertEqual(requests.map { $0.url.absoluteString }, MowanPipelineFixture.apiPaths.map { MowanPipelineFixture.origin + $0 })
            for request in requests {
                XCTAssertEqual(request.method, .get)
                XCTAssertNil(request.body)
                XCTAssertEqual(header("Authorization", in: request), "Bearer fixture-authorization")
                XCTAssertEqual(header("X-Device-ID", in: request), "fixture-device")
                XCTAssertEqual(header("Content-Type", in: request), "application/json")
                XCTAssertEqual(header("User-Agent", in: request), "yuedu_app")
                XCTAssertEqual(header("Referer", in: request), MowanPipelineFixture.origin)
            }
            let inlineCount = await network.recordedInlineCount()
            let unexpected = await network.recordedUnexpectedAddresses()
            XCTAssertEqual(inlineCount, 4)
            XCTAssertTrue(unexpected.isEmpty, "Fixture must reject every unregistered request")
        } catch {
            XCTFail("Mowan \(stage) failed with \(String(reflecting: type(of: error))): \(error)")
        }
    }

    func testOriginalBookURLTemplatePassesTheInterpolatedPathToTaggedJavaScript() throws {
        var stage = "fixture decoding"
        do {
            let fixture = try MowanPipelineFixture.load()
            stage = "original bookUrl field"
            let rule = try XCTUnwrap(fixture.source.ruleSearch?.fields["bookUrl"])
            let context = RuleExecutionContext()
            let address = JSONRuleExtractor(executionContext: context).string(
                from: ["id": "book-fixture-1", "source": "fixture-novel"],
                rule: rule, fallbackKeys: [], variables: ["source": fixture.source]
            )
            XCTAssertEqual(address, inlineAddress("/api/book/detail?source=fixture-novel&book_id=book-fixture-1"))
            XCTAssertNil(context.currentJavaScriptError)
        } catch {
            XCTFail("Mowan \(stage) failed with \(String(reflecting: type(of: error))): \(error)")
        }
    }

    func testOriginalRulesAllowAnonymousSearchDetailCatalogAndContent() async throws {
        let fixture = try MowanPipelineFixture.load()
        let network = MowanPipelineNetwork(responses: fixture.responses)
        let engine = try await makeEngine(network: network, withSavedLogin: false)

        let books = try await engine.searchBooks(source: fixture.source, keyword: "fixture", page: 1).get()
        let book = try XCTUnwrap(books.first)
        XCTAssertEqual(book.bookUrl, inlineAddress("/api/book/detail?source=fixture-novel&book_id=book-fixture-1"))
        let detail = try await engine.getBookDetail(source: fixture.source, book: book).get()
        let chapters = try await engine.getChapterList(source: fixture.source, book: detail).get()
        XCTAssertEqual(chapters.count, fixture.expectedParagraphs.count)
        guard chapters.count == fixture.expectedParagraphs.count else { return }
        for (index, chapter) in chapters.enumerated() {
            let content = try await engine.getContent(source: fixture.source, chapter: chapter).get()
            XCTAssertEqual(content.paragraphs, fixture.expectedParagraphs[index])
        }

        let requests = await network.recordedRequests()
        XCTAssertEqual(requests.map { $0.url.absoluteString }, MowanPipelineFixture.apiPaths.map { MowanPipelineFixture.origin + $0 })
        for request in requests {
            XCTAssertTrue((header("Authorization", in: request) ?? "").isEmpty)
            XCTAssertTrue((header("X-Device-ID", in: request) ?? "").isEmpty)
            XCTAssertTrue((header("Cookie", in: request) ?? "").isEmpty)
            XCTAssertEqual(header("User-Agent", in: request), "yuedu_app")
            XCTAssertEqual(header("Referer", in: request), MowanPipelineFixture.origin)
        }
        let inlineCount = await network.recordedInlineCount()
        let unexpected = await network.recordedUnexpectedAddresses()
        XCTAssertEqual(inlineCount, 4)
        XCTAssertTrue(unexpected.isEmpty)
    }

    func testCatalogHTTPHTMLFailureDoesNotBecomeAnEmptySuccessOrReplayTheRequest() async throws {
        for status in [200, 401, 404] {
            try await assertCatalogHTMLFailure(statusCode: status)
        }
    }

    func testOriginalDiscoverySelectorRecoversFromAPlatformWithoutTabs() async throws {
        let fixture = try MowanPipelineFixture.load()
        let network = MowanPipelineNetwork(responses: fixture.responses)
        let engine = try await makeEngine(network: network, withSavedLogin: false)

        let initial = try await engine.exploreMenu(source: fixture.source).get()
        let selector = try XCTUnwrap(initial.controls.first)
        XCTAssertEqual(selector.kind, .select)
        XCTAssertEqual(selector.title, "请选择平台")
        XCTAssertEqual(selector.defaultValue, "番茄小说")
        XCTAssertTrue(selector.choices.contains("轻小说"))
        XCTAssertTrue(selector.choices.contains("七猫小说"))
        XCTAssertEqual(initial.categories.map(\.title), ["热榜"])
        XCTAssertEqual(initial.categories.map(\.group), ["榜单"])

        let unavailable = try await engine.performExploreAction(source: fixture.source, action: selector.action,
            inputs: [selector.title: "轻小说"]).get()
        XCTAssertTrue(unavailable.menu.categories.isEmpty)
        XCTAssertEqual(unavailable.menu.controls.first?.defaultValue, "轻小说")
        XCTAssertEqual(unavailable.menu.message, "暂无轻小说发现内容")

        let selected = try await engine.performExploreAction(source: fixture.source, action: selector.action,
            inputs: [selector.title: "七猫小说"]).get()
        XCTAssertEqual(selected.menu.controls.first?.defaultValue, "七猫小说")
        XCTAssertEqual(selected.menu.categories.map(\.title), ["玄幻"])
        XCTAssertEqual(selected.menu.categories.map(\.group), ["分类"])
        XCTAssertNil(selected.menu.message)
        let category = try XCTUnwrap(selected.menu.categories.first)
        let discovered = try await engine.exploreBooks(source: fixture.source, url: category.url, page: 1).get()
        XCTAssertEqual(discovered.map(\.name), ["魔丸合成样本"])
        let searched = try await engine.searchBooks(source: fixture.source, keyword: "fixture", page: 1).get()
        XCTAssertEqual(searched.map(\.bookUrl), discovered.map(\.bookUrl))

        let requests = await network.recordedRequests()
        XCTAssertEqual(requests.map { $0.url.absoluteString }, [
            MowanPipelineFixture.origin + "/api/discover/tabs",
            MowanPipelineFixture.origin + "/api/discover/tabs",
            MowanPipelineFixture.origin + "/api/discover/tabs",
            MowanPipelineFixture.origin + "/api/discover/content?source=fixture-qimao&tab=fantasy&page=1&page_size=12",
            MowanPipelineFixture.origin + MowanPipelineFixture.apiPaths[0]
        ])
        let unexpected = await network.recordedUnexpectedAddresses()
        XCTAssertTrue(unexpected.isEmpty)
    }

    func testOriginalDiscoveryFailureRetainsItsNoticeAndPlatformSelector() async throws {
        let fixture = try MowanPipelineFixture.load()
        var responses = fixture.responses
        responses[MowanPipelineFixture.origin + "/api/discover/tabs"] = .init(
            statusCode: 200, contentType: "application/json",
            body: #"{"code":401,"message":"Fixture session unavailable"}"#
        )
        let network = MowanPipelineNetwork(responses: responses)
        let engine = try await makeEngine(network: network, withSavedLogin: false)

        let menu = try await engine.exploreMenu(source: fixture.source).get()

        XCTAssertTrue(menu.categories.isEmpty)
        XCTAssertEqual(menu.controls.first?.kind, .select)
        XCTAssertEqual(menu.message, "请先登陆，登陆后刷新发现页即可")
        let requests = await network.recordedRequests()
        XCTAssertEqual(requests.map { $0.url.path }, ["/api/discover/tabs"])
        let unexpected = await network.recordedUnexpectedAddresses()
        XCTAssertTrue(unexpected.isEmpty)
    }

    private func assertCatalogHTMLFailure(statusCode: Int) async throws {
        var stage = "fixture decoding"
        do {
            let fixture = try MowanPipelineFixture.load()
            var responses = fixture.responses
            responses[MowanPipelineFixture.origin + MowanPipelineFixture.catalogPath] = .init(
                statusCode: statusCode, contentType: "text/html; charset=utf-8",
                body: "<html><body>Fixture login required</body></html>"
            )
            let network = MowanPipelineNetwork(responses: responses)
            stage = "engine setup"
            let engine = try await makeEngine(network: network)
            stage = "search"
            let books = try await engine.searchBooks(source: fixture.source, keyword: "fixture", page: 1).get()
            let book = try XCTUnwrap(books.first)
            stage = "detail"
            let detail = try await engine.getBookDetail(source: fixture.source, book: book).get()

            let result = await engine.getChapterList(source: fixture.source, book: detail)
            guard case .failure(let error) = result else {
                return XCTFail("HTML must not produce chapters: \(result)")
            }
            if statusCode >= 400 {
                guard case .network(let message) = error else { return XCTFail("Expected HTTP failure: \(error)") }
                XCTAssertTrue(message.contains("HTTP \(statusCode)"), message)
            } else {
                guard case .javascript = error else { return XCTFail("Expected JSON.parse failure: \(error)") }
            }
            let requests = await network.recordedRequests()
            XCTAssertEqual(requests.map { $0.url.absoluteString }, Array(MowanPipelineFixture.apiPaths.prefix(3)).map { MowanPipelineFixture.origin + $0 })
            let unexpected = await network.recordedUnexpectedAddresses()
            XCTAssertTrue(unexpected.isEmpty)
        } catch {
            XCTFail("Mowan HTTP \(statusCode) \(stage) failed with \(String(reflecting: type(of: error))): \(error)")
        }
    }

    private func makeEngine(network: MowanPipelineNetwork, withSavedLogin: Bool = true) async throws -> LegadoSourceEngine {
        let cookies = SourceCookieStore(storageURL: nil)
        let origin = try XCTUnwrap(URL(string: MowanPipelineFixture.origin))
        if withSavedLogin {
            for cookie in ["Authorization=Bearer%20fixture-authorization; Path=/", "X-Device-ID=fixture-device; Path=/"] {
                await cookies.storeSetCookieHeaders(["Set-Cookie": cookie], for: origin)
            }
        }
        let engine = LegadoSourceEngine(network: network, cookieStore: cookies,
            scriptCacheStore: SourceScriptCacheStore(isPersistent: false))
        engine.allowWebViewFallback = false
        return engine
    }

    private func inlineAddress(_ path: String) -> String {
        "data:;base64," + Data(path.utf8).base64EncodedString() + #",{"type":"mw"}"#
    }

    private func header(_ name: String, in request: SourceRequest) -> String? {
        request.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

private struct MowanPipelineFixture: Decodable {
    struct Response: Decodable, Sendable {
        let statusCode: Int
        let contentType: String
        let body: String
    }

    let source: BookSource
    let responses: [String: Response]
    let expectedParagraphs: [[String]]

    static let origin = "https://mowan.fixture.invalid"
    static let catalogPath = "/api/book/chapters?source=fixture-novel&book_id=book-fixture-1&type=novel"
    static let contentPaths = [
        "/api/chapter/content?source=fixture-novel&chapter_id=chapter-fixture-1&type=novel",
        "/api/chapter/content?source=fixture-novel&chapter_id=chapter-fixture-2&type=novel"
    ]
    static let apiPaths = [
        "/api/search?keyword=fixture&page=1&page_size=20",
        "/api/book/detail?source=fixture-novel&book_id=book-fixture-1",
        catalogPath
    ] + contentPaths

    static func load() throws -> MowanPipelineFixture {
        let url = TestFixtureSupport.directory("private-bank").appendingPathComponent("mowan-source-pipeline.json")
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

private actor MowanPipelineNetwork: SourceNetworkClient {
    private let responses: [String: MowanPipelineFixture.Response]
    private var requests: [SourceRequest] = []
    private var inlineCount = 0
    private var unexpectedAddresses: [String] = []

    init(responses: [String: MowanPipelineFixture.Response]) { self.responses = responses }

    func recordedRequests() -> [SourceRequest] { requests }
    func recordedInlineCount() -> Int { inlineCount }
    func recordedUnexpectedAddresses() -> [String] { unexpectedAddresses }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        if request.url.scheme == "data" {
            inlineCount += 1
            guard request.shouldReturnInlineHex else {
                return .failure(.rule("Mowan typed envelope did not preserve its hex contract"))
            }
            return SourceInlineEnvelope.response(for: request.url, asHex: request.shouldReturnInlineHex)
        }
        requests.append(request)
        guard let response = responses[request.url.absoluteString] else {
            unexpectedAddresses.append(request.url.absoluteString)
            return .failure(.network("Unexpected request outside the offline Mowan fixture"))
        }
        return .success(SourceResponse(url: request.url, statusCode: response.statusCode,
            headers: ["Content-Type": response.contentType], body: response.body, data: Data(response.body.utf8)))
    }
}
