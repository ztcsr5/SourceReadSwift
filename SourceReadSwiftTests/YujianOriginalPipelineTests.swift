import Foundation
import XCTest
@testable import SourceReadSwift

/// Replays the original four-stage rules and complete library, with documented signing literals redacted.
final class YujianOriginalPipelineTests: XCTestCase {
    func testOriginalRulesRunSearchDetailTOCAndTwoIndependentChapterBodies() async throws {
        let fixture = try YujianPipelineFixture.load()
        let source = try YujianPipelineFixture.loadSource()
        let network = YujianPipelineNetwork(responses: fixture.responses)
        let engine = LegadoSourceEngine(
            network: network,
            cookieStore: SourceCookieStore(storageURL: nil),
            scriptCacheStore: SourceScriptCacheStore(isPersistent: false)
        )
        engine.allowWebViewFallback = false
        engine.persistentState(for: source).put(fixture.sourceVariableJSON, for: "source.variable")

        let books = try await engine.searchBooks(source: source, keyword: fixture.keyword, page: fixture.page).get()
        XCTAssertEqual(books.map(\.name), [fixture.searchName])
        let book = try XCTUnwrap(books.first)
        XCTAssertEqual(book.author, fixture.searchAuthor)
        XCTAssertEqual(book.kind, fixture.searchKind)
        XCTAssertEqual(book.coverUrl, fixture.searchCoverURL)
        XCTAssertEqual(book.bookUrl, fixture.detailURL)
        XCTAssertTrue(book.bookUrl.contains("%2F"), "A slash inside a book ID must remain inside one encoded path segment")

        let detail = try await engine.getBookDetail(source: source, book: book).get()
        XCTAssertEqual(detail.name, fixture.detailName)
        XCTAssertEqual(detail.author, fixture.detailAuthor)
        XCTAssertEqual(detail.kind, fixture.detailKind)
        XCTAssertEqual(detail.coverUrl, fixture.detailCoverURL)
        XCTAssertEqual(detail.tocUrl, fixture.tocURL)
        XCTAssertEqual(detail.latestChapter, fixture.chapters.last?.title)

        let chapters = try await engine.getChapterList(source: source, book: detail).get()
        XCTAssertEqual(chapters.map(\.title), fixture.chapters.map(\.title))
        XCTAssertEqual(chapters.map(\.url), fixture.chapters.map(\.url))
        XCTAssertEqual(chapters.map(\.isVip), fixture.chapters.map(\.isVip))
        XCTAssertEqual(chapters.map(\.bookUrl), Array(repeating: book.bookUrl, count: fixture.chapters.count))
        guard chapters.count == fixture.chapters.count else {
            return XCTFail("Original TOC rules must produce both fixture chapters")
        }
        for (chapter, expected) in zip(chapters, fixture.chapters) {
            XCTAssertTrue(chapter.updateTime?.hasPrefix(expected.updatePrefix) == true)
            let components = try XCTUnwrap(URLComponents(string: chapter.url))
            let items = try XCTUnwrap(components.queryItems)
            XCTAssertEqual(items.count, 4)
            var query: [String: String] = [:]
            for item in items { query[item.name] = item.value }
            XCTAssertEqual(query["bookId"], fixture.bookID, "Use detail BookId, not the different search book_id")
            XCTAssertEqual(query["chapterId"], expected.id)
            XCTAssertEqual(query["vip"], expected.isVip ? "1" : "0")
            XCTAssertEqual(query["chapterTime"], expected.chapterTime)

            let content = try await engine.getContent(source: source, chapter: chapter).get()
            XCTAssertEqual(content.title, expected.title)
            XCTAssertEqual(content.chapter.url, expected.url)
            XCTAssertEqual(content.paragraphs, expected.paragraphs)
            XCTAssertNil(content.nextContentUrl)
        }

        let requests = await network.recordedRequests()
        XCTAssertEqual(requests.map { $0.url.absoluteString }, fixture.requestOrder)
        for request in requests {
            let response = try XCTUnwrap(fixture.responses[request.url.absoluteString])
            XCTAssertEqual(request.method.rawValue, response.method)
            XCTAssertEqual(request.body, response.requestBody.map { Data($0.utf8) })
            XCTAssertEqual(header("Accept", in: request), "application/json")
            XCTAssertEqual(header("X-Reader-Token", in: request), fixture.readerToken)
            XCTAssertFalse(request.webView)
        }
        let searchRequest = try XCTUnwrap(requests.first)
        let searchBody = try XCTUnwrap(searchRequest.body)
        let searchObject = try XCTUnwrap(JSONSerialization.jsonObject(with: searchBody) as? [String: Any])
        XCTAssertEqual(searchObject["keyword"] as? String, fixture.keyword)
        XCTAssertEqual((searchObject["page"] as? NSNumber)?.intValue, fixture.page)
        XCTAssertEqual((searchObject["page_size"] as? NSNumber)?.intValue, 20)
        XCTAssertEqual(header("Content-Type", in: searchRequest), "application/json")
        let rejected = await network.recordedRejectionCount()
        XCTAssertEqual(rejected, 0)
    }

    func testCompleteLibrarySelectsTheFinalYuJianContentDeclaration() throws {
        let source = try YujianPipelineFixture.loadSource()
        let library = try XCTUnwrap(source.raw["jsLib"])
        XCTAssertEqual(library.components(separatedBy: "function YuJianContent(").count - 1, 2)
        let result = try JSCoreRuntime().evaluate(library + "\n; String(YuJianContent).indexOf('contextUrl, response') >= 0;").get()
        XCTAssertEqual(result, "true", "The last declaration passes the full response into comment injection")
    }

    func testOfflineActorRejectsEveryUnregisteredAddress() async throws {
        let fixture = try YujianPipelineFixture.load()
        let network = YujianPipelineNetwork(responses: fixture.responses)
        let request = SourceRequest(
            url: try XCTUnwrap(URL(string: "https://unregistered.fixture.invalid/search")),
            method: .get, headers: [:], body: nil, expectedCharset: nil, timeout: 1
        )
        let result = await network.load(request)
        guard case .failure(let error) = result else {
            return XCTFail("An unregistered URL must never reach a real transport or return fixture success")
        }
        guard case .network(let message) = error else { return XCTFail("Expected offline route rejection") }
        XCTAssertEqual(message, "Unexpected request outside the offline Yujian fixture")
        let rejected = await network.recordedRejectionCount()
        XCTAssertEqual(rejected, 1)
    }

    private func header(_ name: String, in request: SourceRequest) -> String? {
        request.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

private struct YujianPipelineFixture: Decodable {
    struct Chapter: Decodable {
        let id: String
        let title: String
        let url: String
        let isVip: Bool
        let chapterTime: String
        let updatePrefix: String
        let paragraphs: [String]
    }

    struct Response: Decodable, Sendable {
        let method: String
        let requestBody: String?
        let statusCode: Int
        let contentType: String
        let body: String
    }

    let keyword: String
    let page: Int
    let sourceVariableJSON: String
    let readerToken: String
    let searchName: String
    let searchAuthor: String
    let searchKind: String
    let searchCoverURL: String
    let detailName: String
    let detailAuthor: String
    let detailKind: String
    let detailCoverURL: String
    let detailURL: String
    let tocURL: String
    let bookID: String
    let chapters: [Chapter]
    let requestOrder: [String]
    let responses: [String: Response]

    static func load() throws -> Self {
        let url = TestFixtureSupport.directory("yujian").appendingPathComponent("pipeline.json")
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    static func loadSource() throws -> BookSource {
        let url = TestFixtureSupport.directory("yujian").appendingPathComponent("source.json")
        return try JSONDecoder().decode(BookSource.self, from: Data(contentsOf: url))
    }
}

/// There is deliberately no URLSession or fallback transport behind this actor.
private actor YujianPipelineNetwork: SourceNetworkClient {
    private let responses: [String: YujianPipelineFixture.Response]
    private var requests: [SourceRequest] = []
    private var rejectionCount = 0

    init(responses: [String: YujianPipelineFixture.Response]) { self.responses = responses }

    func recordedRequests() -> [SourceRequest] { requests }
    func recordedRejectionCount() -> Int { rejectionCount }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        requests.append(request)
        guard let response = responses[request.url.absoluteString],
              request.method.rawValue == response.method,
              request.body == response.requestBody.map({ Data($0.utf8) }) else {
            rejectionCount += 1
            return .failure(.network("Unexpected request outside the offline Yujian fixture"))
        }
        return .success(SourceResponse(
            url: request.url, statusCode: response.statusCode,
            headers: ["Content-Type": response.contentType],
            body: response.body, data: Data(response.body.utf8)
        ))
    }
}
