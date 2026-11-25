import Foundation
import XCTest
@testable import SourceReadSwift

final class SourceResponseLoginCheckTests: XCTestCase {
    private static let origin = "https://response-check.fixture.invalid"
    private static let payload = #"{"items":[{"name":"Checked","url":"/book/1"}],"name":"Checked","toc":"/toc/1","chapters":[{"title":"Checked","url":"/chapter/1"}],"content":"Checked"}"#

    func testReplacementResponseReachesAllFiveStageParsers() async throws {
        let script = """
            if (result.code() !== 200 || result.header('X-Fixture') !== 'original') {
                throw new Error('response metadata missing');
            }
            Packages.io.legado.app.help.http.StrResponse(result.url(), result.body().replace(/Unchanged/g, 'Checked'));
            """
        for stage in ResponseCheckStage.allCases {
            let network = ResponseCheckNetwork { request, _ in
                .success(Self.response(request, body: Self.payload.replacingOccurrences(of: "Checked", with: "Unchanged")))
            }
            let names = try await run(stage, source: makeSource(script), network: network).get()
            XCTAssertEqual(names, ["Checked"], stage.rawValue)
            let requests = await network.requests
            XCTAssertEqual(requests.count, 1, stage.rawValue)
        }
    }

    func testOriginalResponseIsPreservedAndHookRunsExactlyOnce() async throws {
        let source = makeSource("""
            if (result.url() !== '\(Self.origin)/search' || result.code() !== 201) {
                throw new Error('original response changed');
            }
            if (result.header('X-Fixture') !== 'original') throw new Error('header missing');
            java.ajax('\(Self.origin)/observed');
            result;
            """)
        let network = ResponseCheckNetwork { request, _ in
            .success(Self.response(request, body: Self.payload, status: 201))
        }
        let names = try await run(.search, source: source, network: network).get()
        XCTAssertEqual(names, ["Checked"])
        let paths = await network.requests.map(\.url.path)
        XCTAssertEqual(paths, ["/search", "/observed"])
    }

    func testThrowingHookFailsWithoutReplayingItsSideEffects() async {
        let source = makeSource("""
            java.ajax('\(Self.origin)/observed');
            throw new Error('synthetic response check failure');
            """)
        let network = ResponseCheckNetwork { request, _ in
            .success(Self.response(request, body: Self.payload))
        }
        let result = await run(.search, source: source, network: network)
        guard case .failure(.javascript(let message)) = result else {
            return XCTFail("A throwing response hook must produce a JavaScript failure")
        }
        XCTAssertTrue(message.contains("synthetic response check failure"))
        let paths = await network.requests.map(\.url.path)
        XCTAssertEqual(paths, ["/search", "/observed"])
    }

    func testNullArgumentsResendCurrentPostWithLatestCookieBeforeHTTPFailure() async throws {
        let source = makeSource(
            """
            if (result.code() === 401) {
                if (java.get('cookieHeader').indexOf('fixture_session=renewed') < 0) throw new Error('current cookie missing');
                result = java.getStrResponse(null, null);
            }
            result;
            """,
            searchURL: Self.origin + #"/search,{"method":"POST","headers":{"Content-Type":"application/x-www-form-urlencoded","X-Route":"kept"},"body":"term=fixture&cursor=2"}"#)
        let network = ResponseCheckNetwork { request, sequence in
            if sequence == 1 {
                return .success(Self.response(request, body: "login required", status: 401,
                    headers: ["Set-Cookie": "fixture_session=renewed; Path=/; HttpOnly"]))
            }
            return .success(Self.response(request, body: Self.payload))
        }
        let names = try await run(.search, source: source, network: network).get()
        XCTAssertEqual(names, ["Checked"])
        let requests = await network.requests
        XCTAssertEqual(requests.count, 2)
        guard requests.count == 2 else { return }
        for request in requests {
            XCTAssertEqual(request.url.absoluteString, Self.origin + "/search")
            XCTAssertEqual(request.method, .post)
            XCTAssertEqual(request.body, Data("term=fixture&cursor=2".utf8))
            XCTAssertEqual(request.headers["X-Route"], "kept")
            XCTAssertEqual(request.headers["Content-Type"], "application/x-www-form-urlencoded")
        }
        XCTAssertNil(requests[0].headers["Cookie"])
        XCTAssertEqual(requests[1].headers["Cookie"], "fixture_session=renewed")
    }

    func testScriptResendDoesNotRecursivelyInvokeTheResponseHook() async throws {
        let source = makeSource("java.getStrResponse(null, null)")
        let network = ResponseCheckNetwork { request, sequence in
            guard sequence <= 4 else { return .failure(.network("fixture recursion guard")) }
            return .success(Self.response(request, body: Self.payload))
        }
        let names = try await run(.search, source: source, network: network).get()
        XCTAssertEqual(names, ["Checked"])
        let requests = await network.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testRepeatedScriptResendsStopAtABoundedBudget() async {
        let source = makeSource("for (var i = 0; i < 32; i++) result = java.getStrResponse(null, null); result;")
        let network = ResponseCheckNetwork { request, _ in
            .success(Self.response(request, body: Self.payload))
        }
        let result = await run(.search, source: source, network: network)
        guard case .failure = result else { return XCTFail("Response resends exhausted no request budget") }
        let requests = await network.requests
        XCTAssertGreaterThan(requests.count, 1)
        XCTAssertLessThan(requests.count, 33)
    }

    func testCancellationDiscardsLateFirstResponseBeforeHookCanResend() async {
        let entered = expectation(description: "initial response held")
        let gate = ResponseCheckGate()
        let source = makeSource("java.getStrResponse(null, null)")
        let network = ResponseCheckNetwork { request, sequence in
            if sequence == 1 {
                entered.fulfill()
                await gate.wait()
            }
            return .success(Self.response(request, body: Self.payload))
        }
        let task = Task { await run(.search, source: source, network: network) }
        await fulfillment(of: [entered], timeout: 2)
        task.cancel()
        await gate.open()
        let result = await task.value
        guard case .failure = result else { return XCTFail("Cancelled response check returned success") }
        let requests = await network.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testCancellationDuringResendPreventsAnotherRequest() async {
        let entered = expectation(description: "response resend held")
        let gate = ResponseCheckGate()
        let source = makeSource("for (var i = 0; i < 4; i++) result = java.getStrResponse(null, null); result;")
        let network = ResponseCheckNetwork { request, sequence in
            if sequence == 2 {
                entered.fulfill()
                await gate.wait()
            }
            return .success(Self.response(request, body: Self.payload))
        }
        let task = Task { await run(.search, source: source, network: network) }
        await fulfillment(of: [entered], timeout: 2)
        task.cancel()
        await gate.open()
        let result = await task.value
        guard case .failure = result else { return XCTFail("Cancelled response resend returned success") }
        let requests = await network.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testCaughtResendBudgetFailureStillFailsTheStage() async {
        let source = makeSource("try { for (var i = 0; i < 32; i++) java.getStrResponse(null, null); } catch (_) {} result;")
        let network = ResponseCheckNetwork { request, _ in
            .success(Self.response(request, body: Self.payload))
        }
        let result = await run(.search, source: source, network: network)
        guard case .failure = result else { return XCTFail("A caught resend budget error returned success") }
        let requests = await network.requests
        XCTAssertGreaterThan(requests.count, 1)
        XCTAssertLessThan(requests.count, 33)
    }

    func testBooleanHookCompletionPreservesTheOriginalResponse() async throws {
        let network = ResponseCheckNetwork { request, _ in
            .success(Self.response(request, body: Self.payload))
        }
        let names = try await run(.search, source: makeSource("result.code() === 200"), network: network).get()
        XCTAssertEqual(names, ["Checked"])
        let requests = await network.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testAJAXVerificationCompletionPreservesTheOriginalResponse() async throws {
        let network = ResponseCheckNetwork { request, _ in
            .success(Self.response(request, body: request.url.path == "/verify" ? "true" : Self.payload))
        }
        let source = makeSource("java.ajax('\(Self.origin)/verify')")
        let names = try await run(.search, source: source, network: network).get()
        XCTAssertEqual(names, ["Checked"])
        let paths = await network.requests.map(\.url.path)
        XCTAssertEqual(paths, ["/search", "/verify"])
    }

    func testDirectoryAndContentAdditionalPagesDoNotReplayFirstResponseHook() async throws {
        let source = makeSource("""
            java.ajax('\(Self.origin)/observed');
            result;
            """, includesPagination: true)
        let network = ResponseCheckNetwork { request, _ in
            let body: String
            switch request.url.path {
            case "/toc/1":
                body = #"{"chapters":[{"title":"First","url":"/chapter/1"}],"next":"/toc/2"}"#
            case "/toc/2":
                body = #"{"chapters":[{"title":"Second","url":"/chapter/2"}],"next":""}"#
            case "/chapter/1": body = #"{"content":"First","next":"/chapter/2"}"#
            case "/chapter/2": body = #"{"content":"Second","next":""}"#
            case "/observed": body = "observed"
            default: return .failure(.network("unexpected pagination fixture path"))
            }
            return .success(Self.response(request, body: body))
        }
        let chapterNames = try await run(.toc, source: source, network: network).get()
        let paragraphs = try await run(.content, source: source, network: network).get()
        XCTAssertEqual(chapterNames, ["First", "Second"])
        XCTAssertEqual(paragraphs, ["First", "Second"])
        let paths = await network.requests.map(\.url.path)
        XCTAssertEqual(paths, ["/toc/1", "/observed", "/toc/2", "/chapter/1", "/observed", "/chapter/2"])
    }

    private func makeSource(_ script: String, searchURL: String? = nil, includesPagination: Bool = false) -> BookSource {
        let listing = SourceRule(fields: ["bookList": "$.items[*]", "name": "$.name", "bookUrl": "$.url"])
        return BookSource(bookSourceName: "Response check fixture", bookSourceUrl: Self.origin,
            searchUrl: searchURL ?? Self.origin + "/search", ruleSearch: listing,
            ruleBookInfo: .init(fields: ["name": "$.name", "tocUrl": "$.toc"]),
            ruleToc: .init(fields: ["chapterList": "$.chapters[*]", "chapterName": "$.title",
                "chapterUrl": "$.url", "nextTocUrl": includesPagination ? "$.next" : ""]),
            ruleContent: .init(fields: ["content": "$.content", "nextContentUrl": includesPagination ? "$.next" : ""]),
            ruleExplore: listing, loginCheckJs: script)
    }

    private func run(_ stage: ResponseCheckStage, source: BookSource,
                     network: ResponseCheckNetwork) async -> Result<[String], SourceEngineError> {
        let engine = LegadoSourceEngine(network: network, cookieStore: SourceCookieStore(storageURL: nil))
        engine.allowWebViewFallback = false
        let book = SearchBook(name: "Fixture", author: nil, coverUrl: nil,
            bookUrl: Self.origin + "/book/1", sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl)
        switch stage {
        case .search:
            return await engine.searchBooks(source: source, keyword: "fixture", page: 1).map { $0.map(\.name) }
        case .explore:
            return await engine.exploreBooks(source: source, url: Self.origin + "/explore", page: 1).map { $0.map(\.name) }
        case .detail:
            return await engine.getBookDetail(source: source, book: book).map { [$0.name] }
        case .toc:
            let detail = BookDetail(name: book.name, author: nil, coverUrl: nil, bookUrl: book.bookUrl,
                tocUrl: Self.origin + "/toc/1", sourceName: book.sourceName, sourceUrl: book.sourceUrl,
                intro: nil, latestChapter: nil)
            return await engine.getChapterList(source: source, book: detail).map { $0.map(\.title) }
        case .content:
            let chapter = BookChapter(title: "Fixture", url: Self.origin + "/chapter/1", bookUrl: book.bookUrl, index: 0)
            return await engine.getContent(source: source, chapter: chapter).map(\.paragraphs)
        }
    }

    private static func response(_ request: SourceRequest, body: String, status: Int = 200,
                                 headers: [String: String] = [:]) -> SourceResponse {
        SourceResponse(url: request.url, statusCode: status,
            headers: headers.merging(["Content-Type": "application/json", "X-Fixture": "original"]) { original, _ in original },
            body: body, data: Data(body.utf8))
    }
}

private enum ResponseCheckStage: String, CaseIterable {
    case search, explore, detail, toc, content
}

private actor ResponseCheckNetwork: SourceNetworkClient {
    private(set) var requests: [SourceRequest] = []
    private let reply: @Sendable (SourceRequest, Int) async -> Result<SourceResponse, SourceEngineError>

    init(reply: @escaping @Sendable (SourceRequest, Int) async -> Result<SourceResponse, SourceEngineError>) {
        self.reply = reply
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        requests.append(request)
        return await reply(request, requests.count)
    }
}

private actor ResponseCheckGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
