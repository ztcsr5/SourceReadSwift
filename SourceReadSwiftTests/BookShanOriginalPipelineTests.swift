import Foundation
import XCTest
@testable import SourceReadSwift

/// Executes the original stage code and packed content; unused crypto constants are redacted.
final class BookShanOriginalPipelineTests: XCTestCase {
    func testOriginalNovelRulesKeepTwoIndependentChaptersAndTheirVolume() async throws {
        try await replayPipeline(isFanqie: false)
    }

    func testOriginalFanqieRulesKeepBookAndItemIdentifiersThroughThePackedContentScript() async throws {
        try await replayPipeline(isFanqie: true)
    }

    private func replayPipeline(isFanqie: Bool) async throws {
        let fixtureURL = TestFixtureSupport.directory("bookshan").appendingPathComponent("source.json")
        let source = try JSONDecoder().decode(BookSource.self, from: Data(contentsOf: fixtureURL))
        let network = BookShanOriginalNetwork(isFanqie: isFanqie)
        let engine = LegadoSourceEngine(
            network: network,
            cookieStore: SourceCookieStore(storageURL: nil),
            scriptCacheStore: SourceScriptCacheStore(isPersistent: false)
        )
        engine.allowWebViewFallback = false
        let configuration: [[String: Any]] = [[
            "host": BookShanOriginalRoutes.origin, "gender": "male", "tag": "all",
            "yunpara": "0", "book_sync": "off", "fqdown": "off", "simple_intro": "on",
            "lastUpdateCheck": Date().timeIntervalSince1970 * 1_000
        ]]
        let configurationJSON = try JSONSerialization.data(withJSONObject: configuration)
        let state = engine.persistentState(for: source)
        state.put(String(decoding: configurationJSON, as: UTF8.self), for: "source.variable")
        state.put(BookShanOriginalRoutes.loginHeader, for: "source.loginHeader")

        let books = try await engine.searchBooks(source: source, keyword: "fixture", page: 1).get()
        XCTAssertEqual(books.map(\.name), ["书山合成样本"])
        let book = try XCTUnwrap(books.first)
        let detailEnvelope = try decodeEnvelope(book.bookUrl, stage: "detailsUrl", expectedType: "susan")
        XCTAssertEqual(detailEnvelope["source"], network.sourceName)
        XCTAssertEqual(detailEnvelope["url"], BookShanOriginalRoutes.book)

        let detail = try await engine.getBookDetail(source: source, book: book).get()
        XCTAssertEqual(detail.name, "书山合成样本·详情")
        XCTAssertEqual(detail.author, "Fixture Detail Author")
        let expectedIntro = isFanqie ? "原规则补取的番茄增强简介" : "离线详情合成简介"
        XCTAssertTrue(detail.intro?.contains(expectedIntro) == true)
        let catalogEnvelope = try decodeEnvelope(try XCTUnwrap(detail.tocUrl), stage: "catalogUrl", expectedType: "susan")
        XCTAssertEqual(catalogEnvelope["source"], network.sourceName)
        XCTAssertEqual(catalogEnvelope["bookid"], BookShanOriginalRoutes.bookID)

        let chapters = try await engine.getChapterList(source: source, book: detail).get()
        XCTAssertEqual(chapters.map(\.title), ["第一章·合成起点", "第二章·合成终点"])
        XCTAssertEqual(chapters.map(\.volumeName), ["第一卷", "第一卷"])
        XCTAssertEqual(chapters.map(\.bookUrl), [book.bookUrl, book.bookUrl])
        guard chapters.count == BookShanOriginalRoutes.chapterIDs.count else {
            return XCTFail("The original catalog must keep both independent fixture chapters")
        }
        for (index, chapter) in chapters.enumerated() {
            let envelope = try decodeEnvelope(chapter.url, stage: "chapterUrl", expectedType: "qingci")
            XCTAssertEqual(envelope["cid"], BookShanOriginalRoutes.chapterIDs[index])
            XCTAssertEqual(envelope["source"], network.sourceName)
            if isFanqie {
                XCTAssertEqual(envelope["book_id"], BookShanOriginalRoutes.bookID)
                XCTAssertEqual(envelope["item_id"], BookShanOriginalRoutes.itemIDs[index])
                XCTAssertNil(envelope["url"])
            } else {
                XCTAssertEqual(envelope["url"], BookShanOriginalRoutes.book)
                XCTAssertNil(envelope["item_id"])
            }
            let content = try await engine.getContent(source: source, chapter: chapter).get()
            XCTAssertEqual(content.paragraphs, BookShanOriginalRoutes.paragraphs[index])
        }

        let requests = await network.recordedRequests()
        let expectedPaths = ["/search", "/details"] + (isFanqie ? ["/detail"] : [])
            + ["/catalog", "/content", "/content"]
        XCTAssertEqual(requests.map { $0.url.path }, expectedPaths)
        for request in requests {
            XCTAssertEqual(request.url.host, "bookshan.fixture.invalid")
            XCTAssertEqual(header("X-Api-Key", in: request),
                Data(BookShanOriginalRoutes.loginHeader.utf8).base64EncodedString())
            XCTAssertEqual(header("X-Novel-Token", in: request), "fixture-novel-token")
        }
        let inlineCount = await network.recordedInlineCount()
        let failures = await network.recordedFailures()
        XCTAssertEqual(inlineCount, 4)
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "; "))
    }

    private func decodeEnvelope(_ address: String, stage: String, expectedType: String) throws -> [String: String] {
        let prefix = "data:\(stage);base64,"
        XCTAssertTrue(address.hasPrefix(prefix))
        guard address.hasPrefix(prefix), let metadata = address.range(of: ",{", options: .backwards) else {
            throw SourceEngineError.rule("Original BookShan rule did not produce a typed data envelope")
        }
        let encoded = String(address[address.index(address.startIndex, offsetBy: prefix.count)..<metadata.lowerBound])
        let payload = try XCTUnwrap(Data(base64Encoded: encoded))
        let options = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(address[metadata.lowerBound...].dropFirst().utf8)) as? [String: String]
        )
        XCTAssertEqual(options["type"], expectedType)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: String])
    }

    private func header(_ name: String, in request: SourceRequest) -> String? {
        request.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

private enum BookShanOriginalRoutes {
    static let origin = "https://bookshan.fixture.invalid"
    static let book = origin + "/books/1"
    static let cover = origin + "/cover.png"
    static let bookID = "fixture-book-id"
    static let chapterIDs = ["fixture-chapter-1", "fixture-chapter-2"]
    static let itemIDs = ["1000000000000000001", "1000000000000000002"]
    static let loginHeader = #"{"authorization":"fixture-only"}"#
    static let paragraphs = [["第一章第一段合成正文。", "第一章第二段合成正文。"],
        ["第二章第一段合成正文。", "第二章第二段合成正文。"]]
}

private actor BookShanOriginalNetwork: SourceNetworkClient {
    nonisolated let sourceName: String
    private let isFanqie: Bool
    private var requests: [SourceRequest] = []
    private var inlineCount = 0
    private var failures: [String] = []

    init(isFanqie: Bool) {
        self.isFanqie = isFanqie
        sourceName = isFanqie ? "番茄小说" : "fixture-novel"
    }

    func recordedRequests() -> [SourceRequest] { requests }
    func recordedInlineCount() -> Int { inlineCount }
    func recordedFailures() -> [String] { failures }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        if request.url.scheme == "data" {
            inlineCount += 1
            guard request.shouldReturnInlineHex else { return reject("Typed envelope lost its hex flag") }
            return SourceInlineEnvelope.response(for: request.url, asHex: request.shouldReturnInlineHex)
        }
        requests.append(request)
        guard request.url.scheme == "https", request.url.host == "bookshan.fixture.invalid",
              request.url.port == nil, request.url.user == nil, request.url.password == nil else {
            return reject("Request escaped the offline BookShan origin")
        }
        do {
            let payload = try payload(for: request)
            let bytes = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            return .success(SourceResponse(url: request.url, statusCode: 200,
                headers: ["Content-Type": "application/json"], body: String(decoding: bytes, as: UTF8.self), data: bytes))
        } catch {
            return reject("BookShan fixture rejected method, query or JSON body at \(request.url.path)")
        }
    }

    private func payload(for request: SourceRequest) throws -> [String: Any] {
        let origin = BookShanOriginalRoutes.self
        switch request.url.path {
        case "/search":
            try require(request, method: .get, query: ["login": "search", "key": "fixture", "page": "1"])
            return ["code": 0, "data": [["source": sourceName, "book_url": origin.book,
                "title": "书山合成样本", "author": "Fixture Author",
                "cover": origin.cover, "desc": "离线搜索合成简介"]]]
        case "/details":
            try require(request, method: .post, body: ["source": sourceName, "url": origin.book,
                "cover": origin.cover, "desc": "离线搜索合成简介", "name": "书山合成样本"])
            return ["code": 0, "data": ["source": sourceName, "book_url": origin.book,
                "title": "书山合成样本·详情", "author": "Fixture Detail Author",
                "bookid": origin.bookID, "tab": "novel", "cover": origin.cover, "desc": "离线详情合成简介"]]
        case "/detail" where isFanqie:
            try require(request, method: .get, query: ["book_id": origin.bookID])
            return ["code": 0, "data": ["abstract": "原规则补取的番茄增强简介"]]
        case "/catalog":
            try require(request, method: .post, body: ["source": sourceName, "url": origin.book,
                "name": "书山合成样本·详情", "bookid": origin.bookID, "tab": "novel"])
            let chapters = origin.chapterIDs.enumerated().map { index, identifier -> [String: Any] in
                ["cid": identifier, "title": index == 0 ? "第一章·合成起点" : "第二章·合成终点",
                    "url": origin.origin + "/chapters/\(index + 1)?item_id=" + origin.itemIDs[index]]
            }
            return ["code": 0, "data": [["cid": "fixture-volume", "title": "第一卷", "isVolume": true]] + chapters]
        case "/content":
            let body = try XCTUnwrap(request.body)
            let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
            let index = try XCTUnwrap(origin.chapterIDs.firstIndex(of: decoded["cid"] ?? ""))
            var expected = ["cid": origin.chapterIDs[index], "source": sourceName, "version": "12"]
            if isFanqie {
                expected["book_id"] = origin.bookID
                expected["item_id"] = origin.itemIDs[index]
                expected["commentUrl"] = origin.origin + "/idea_comment?book_id=" + origin.bookID
                    + "&item_id=" + origin.itemIDs[index] + "&sessionid="
            } else {
                expected["url"] = origin.book
                expected["commentUrl"] = ""
            }
            try require(request, method: .post, body: expected)
            return ["code": 0, "data": ["content": origin.paragraphs[index].joined(separator: "\n"), "tab": "novel"]]
        default:
            throw SourceEngineError.rule("Unregistered BookShan fixture route")
        }
    }

    private func require(_ request: SourceRequest, method: SourceHTTPMethod,
                         query: [String: String] = [:], body: [String: String]? = nil) throws {
        guard request.method == method, let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false) else {
            throw SourceEngineError.rule("Unexpected BookShan fixture method")
        }
        let queryItems = components.queryItems ?? []
        let actualQuery = queryItems.reduce(into: [String: String]()) { $0[$1.name] = $1.value ?? "" }
        guard actualQuery == query, queryItems.count == query.count else {
            throw SourceEngineError.rule("Unexpected BookShan fixture query")
        }
        if let body {
            let bytes = try XCTUnwrap(request.body)
            let actual = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: String])
            guard actual == body else { throw SourceEngineError.rule("Unexpected BookShan fixture JSON body") }
        } else if request.body != nil {
            throw SourceEngineError.rule("Unexpected BookShan fixture body")
        }
    }

    private func reject(_ message: String) -> Result<SourceResponse, SourceEngineError> {
        failures.append(message)
        return .failure(.network(message))
    }
}
