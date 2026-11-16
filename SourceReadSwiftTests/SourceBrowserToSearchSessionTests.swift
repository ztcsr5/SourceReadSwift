import XCTest
@testable import SourceReadSwift

/// Runs production request building and URLSession after a browser-only login.
final class SourceBrowserToSearchSessionTests: XCTestCase {
    override func tearDown() {
        BrowserSearchURLProtocol.requests.reset()
        super.tearDown()
    }

    func testBrowserOnlyLoginFeedsFreshCookieToNextTopLevelSearch() async throws {
        let fixture = await makeFixture()
        defer { fixture.session.invalidateAndCancel() }
        let source = makeSource()
        try await completeBrowserLogin(engine: fixture.engine, source: source)
        XCTAssertTrue(BrowserSearchURLProtocol.requests.snapshot.isEmpty, "Login must not run an ajax workaround")
        let current = await fixture.cookies.cookieHeader(for: URL(string: source.bookSourceUrl)!)
        XCTAssertEqual(current, "session=browser-new")
        let books = try await fixture.engine.searchBooks(source: source, keyword: "fixture", page: 1).get()
        XCTAssertEqual(books.first?.name, "Fixture book")
        let request = try XCTUnwrap(BrowserSearchURLProtocol.requests.snapshot.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "session=browser-new")
    }

    func testBrowserOnlyLoginFeedsFreshCookieToNextTopLevelChapter() async throws {
        let fixture = await makeFixture()
        defer { fixture.session.invalidateAndCancel() }
        let source = makeSource()
        try await completeBrowserLogin(engine: fixture.engine, source: source)
        let chapter = BookChapter(title: "Fixture chapter", url: "https://login.fixture.invalid/chapter",
            bookUrl: "https://login.fixture.invalid/book", index: 0)
        let content = try await fixture.engine.getContent(source: source, chapter: chapter, maxPages: 1).get()
        XCTAssertFalse(content.paragraphs.isEmpty)
        let request = try XCTUnwrap(BrowserSearchURLProtocol.requests.snapshot.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "session=browser-new")
    }

    func testTopLevelSearchAtAnotherHostDoesNotUseLoginHostSnapshot() async throws {
        let fixture = await makeFixture()
        defer { fixture.session.invalidateAndCancel() }
        let source = makeSource(searchURL: "https://other.fixture.invalid/search?q={{key}}")
        try await completeBrowserLogin(engine: fixture.engine, source: source)
        _ = try await fixture.engine.searchBooks(source: source, keyword: "fixture", page: 1).get()
        let request = try XCTUnwrap(BrowserSearchURLProtocol.requests.snapshot.first)
        XCTAssertEqual(request.url?.host, "other.fixture.invalid")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    }

    func testDisablingAutomaticSnapshotKeepsAuthorCookieAndLegacyDefault() {
        let source = BookSource(bookSourceName: "Author cookie", bookSourceUrl: "https://fixture.invalid",
            header: #"{"Cookie":"session=author"}"#)
        let values = ["cookieHeader": "session=stale"]
        let current = SourceRequestBuilder(usesCookieSnapshot: false).buildPageRequest(
            source: source, urlText: "/book", persistentValues: values)
        XCTAssertEqual(current.headers["Cookie"], "session=author")
        let legacy = SourceRequestBuilder().buildPageRequest(source: source, urlText: "/book", persistentValues: values)
        XCTAssertEqual(legacy.headers["Cookie"], "session=stale")
    }

    func testInjectedTopLevelResponseUpdatesSharedJarBeforeNextChapter() async throws {
        let cookies = SourceCookieStore(storageURL: nil)
        let network = BrowserSearchFixtureNetwork()
        let engine = LegadoSourceEngine(network: network, cookieStore: cookies)
        let source = makeSource()
        _ = try await engine.searchBooks(source: source, keyword: "fixture", page: 1).get()
        let stored = await cookies.cookieHeader(for: URL(string: source.bookSourceUrl)!)
        XCTAssertEqual(stored, "session=from-search")
        let chapter = BookChapter(title: "Fixture", url: "https://login.fixture.invalid/chapter",
            bookUrl: "https://login.fixture.invalid/book", index: 0)
        _ = try await engine.getContent(source: source, chapter: chapter, maxPages: 1).get()
        let requests = await network.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.headers["Cookie"], "session=from-search")
    }

    func testSyntheticPayActionLoadsAnonymousLibraryAndNeverPurchases() async throws {
        let fixture = await makeFixture()
        defer { fixture.session.invalidateAndCancel() }
        let source = BookSource(bookSourceName: "No purchase fixture", bookSourceUrl: "https://login.fixture.invalid",
            raw: ["jsLib": #"{"fixture":"https://login.fixture.invalid/library.js"}"#])
        let chapter = BookChapter(title: "Fixture", url: "https://login.fixture.invalid/chapter",
            bookUrl: "https://login.fixture.invalid/book", index: 0)
        let outcome = try await fixture.engine.performPayAction(source: source, chapter: chapter,
            payAction: "fixtureNoPurchase()").get()
        guard case .failed = outcome else { return XCTFail("This fixture must not report a purchase") }
        XCTAssertEqual(fixture.engine.persistentState(for: source).get("source.variable.fixtureLibrary"), "loaded")
        let requests = BrowserSearchURLProtocol.requests.snapshot
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.path, "/library.js")
        XCTAssertEqual(requests.first?.httpMethod, "GET")
        XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Cookie"))
    }

    private func makeSource(searchURL: String = "https://login.fixture.invalid/search?q={{key}}") -> BookSource {
        BookSource(bookSourceName: "Browser to listing", bookSourceUrl: "https://login.fixture.invalid",
            searchUrl: searchURL,
            ruleSearch: SourceRule(fields: ["bookList": "$.books[*]", "name": "$.name", "bookUrl": "$.url"]),
            ruleContent: SourceRule(fields: ["content": "$.body"]),
            loginUi: #"[{"name":"account","type":"text"}]"#)
    }

    private func completeBrowserLogin(engine: LegadoSourceEngine, source: BookSource) async throws {
        _ = try await engine.performLoginInteraction(source: source,
            action: "java.startBrowserAwait('https://login.fixture.invalid/login', 'Fixture', false);", credentials: [:]).get()
    }

    private func makeFixture() async -> (engine: LegadoSourceEngine, cookies: SourceCookieStore, session: URLSession) {
        let cookies = SourceCookieStore(storageURL: nil)
        await cookies.storeSetCookieHeaders(["Set-Cookie": "session=before-browser; Path=/"],
            for: URL(string: "https://login.fixture.invalid")!)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.protocolClasses = [BrowserSearchURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let network = URLSessionSourceNetworkClient(session: session, cookieStore: cookies)
        let engine = LegadoSourceEngine(network: network, cookieStore: cookies, browserLoginProvider: { url, _ in
            _ = SourceScriptCookieBridge(store: cookies).perform(.write(url, "session=browser-new; Path=/"))
            return SourceResponse(url: URL(string: "https://login.fixture.invalid/account")!, statusCode: 200,
                headers: [:], body: "<p>Signed in</p>", data: Data("<p>Signed in</p>".utf8))
        })
        engine.allowWebViewFallback = false
        return (engine, cookies, session)
    }
}

private actor BrowserSearchFixtureNetwork: SourceNetworkClient {
    private(set) var requests: [SourceRequest] = []
    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        requests.append(request)
        let isSearch = request.url.path == "/search"
        let body = isSearch ? #"{"books":[{"name":"Fixture book","url":"/book"}]}"#
            : #"{"body":"正文第一段。这里是一段通过真实生产解析器读取的正文，用于验证顶层响应会话同步。"}"#
        let headers = isSearch ? ["Content-Type": "application/json", "Set-Cookie": "session=from-search; Path=/"]
            : ["Content-Type": "application/json"]
        return .success(SourceResponse(url: request.url, statusCode: 200, headers: headers, body: body, data: Data(body.utf8)))
    }
}

private final class BrowserSearchURLProtocol: URLProtocol {
    final class Requests: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [URLRequest] = []
        var snapshot: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
        func append(_ request: URLRequest) { lock.lock(); defer { lock.unlock() }; recorded.append(request) }
        func reset() { lock.lock(); defer { lock.unlock() }; recorded = [] }
    }

    static let requests = Requests()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let body: String
        let contentType: String
        switch url.path {
        case "/search":
            body = #"{"books":[{"name":"Fixture book","url":"/book"}]}"#
            contentType = "application/json"
        case "/chapter":
            body = #"{"body":"正文第一段。这里是一段足够长的阅读内容，用于验证网页登录完成后的正文请求使用新会话。"}"#
            contentType = "application/json"
        case "/library.js":
            body = "function fixtureNoPurchase() { source.put('fixtureLibrary', 'loaded'); return 'false'; }"
            contentType = "application/javascript"
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
