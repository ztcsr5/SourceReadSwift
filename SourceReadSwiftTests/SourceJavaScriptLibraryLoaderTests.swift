import XCTest
@testable import SourceReadSwift

final class SourceJavaScriptLibraryLoaderTests: XCTestCase {
    func testManifestPreservesDeclarationOrderIncludingNumericKeysAndEscapedNames() throws {
        let urls = try XCTUnwrap(SourceJavaScriptLibraryLoader.remoteURLs(in:
            #"{"10":"https://fixture.invalid/base.js","2":"http://fixture.invalid/dependent.js","a\"b":"https://fixture.invalid/last.js"}"#).get())
        XCTAssertEqual(urls.map(\.lastPathComponent), ["base.js", "dependent.js", "last.js"])
        XCTAssertNil(try SourceJavaScriptLibraryLoader.remoteURLs(in: "function inlineLibrary() { return 42; }").get())
        XCTAssertEqual(try SourceJavaScriptLibraryLoader.remoteURLs(in: "{}").get(), [])
    }

    func testManifestRejectsNonWebCredentialsAndNonStringValues() {
        for manifest in [#"{"bad":"file:///private/script.js"}"#,
                         #"{"bad":"https://name:secret@fixture.invalid/script.js"}"#,
                         #"{"bad":42}"#] {
            guard case .failure = SourceJavaScriptLibraryLoader.remoteURLs(in: manifest) else {
                XCTFail("Invalid library manifest must not become inline JavaScript")
                continue
            }
        }
    }

    func testAnonymousRequestAndSuccessfulResponseAreCached() async throws {
        let network = LibraryFixtureNetwork()
        let loader = SourceJavaScriptLibraryLoader(network: network)
        let url = URL(string: "https://cdn.fixture.invalid/library.js")!
        let first = try await loader.load(url).get()
        XCTAssertEqual(first, "var fixture = 1;")
        _ = try await loader.load(url).get()
        let requests = await network.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, .get)
        XCTAssertFalse(request.usesCookies)
        XCTAssertNil(request.headers["Cookie"])
        XCTAssertNil(request.headers["Authorization"])
        XCTAssertNil(request.body)
        XCTAssertFalse(request.webView)
    }

    func testConcurrentRequestsShareOneDownload() async throws {
        let network = LibraryFixtureNetwork(delay: 50_000_000)
        let loader = SourceJavaScriptLibraryLoader(network: network)
        let url = URL(string: "https://fixture.invalid/library.js")!
        async let first = loader.load(url)
        async let second = loader.load(url)
        let (left, right) = await (first, second)
        XCTAssertEqual(try left.get(), try right.get())
        let requests = await network.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testExpiredLibraryIsDownloadedAgain() async throws {
        let clock = LibraryFixtureClock()
        let network = LibraryFixtureNetwork()
        let loader = SourceJavaScriptLibraryLoader(network: network,
            limits: .init(lifetime: 10), now: { clock.read() })
        let url = URL(string: "https://fixture.invalid/library.js")!
        _ = try await loader.load(url).get()
        clock.advance(11)
        _ = try await loader.load(url).get()
        let requests = await network.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testCacheEvictsLeastRecentlyUsedEntryAndHonorsTotalBytes() async throws {
        let network = LibraryFixtureNetwork(body: "a=1")
        let loader = SourceJavaScriptLibraryLoader(network: network,
            limits: .init(maxEntries: 2, maxBytes: 6, maxLibraryBytes: 6))
        let urls = (0..<3).map { URL(string: "https://fixture.invalid/\($0).js")! }
        for url in urls.prefix(2) { _ = try await loader.load(url).get() }
        _ = try await loader.load(urls[0]).get()
        _ = try await loader.load(urls[2]).get()
        _ = try await loader.load(urls[1]).get()
        let requests = await network.requests
        XCTAssertEqual(requests.map(\.url), [urls[0], urls[1], urls[2], urls[1]])

        let byteNetwork = LibraryFixtureNetwork(body: "a=1")
        let byteLoader = SourceJavaScriptLibraryLoader(network: byteNetwork,
            limits: .init(maxEntries: 32, maxBytes: 5, maxLibraryBytes: 5))
        for url in [urls[0], urls[1], urls[0]] { _ = try await byteLoader.load(url).get() }
        let byteRequests = await byteNetwork.requests
        XCTAssertEqual(byteRequests.count, 3)
    }

    func testOversizedFailedAndHTMLResponsesAreRejectedAndNotCached() async {
        let fixtures = [(LibraryFixtureNetwork(body: "var tooLong = true;"), 8, "大小上限"),
                        (LibraryFixtureNetwork(body: "missing", status: 404), 1_024, "HTTP 404"),
                        (LibraryFixtureNetwork(body: "<html>login</html>", contentType: "text/html"), 1_024, "未取得 JavaScript"),
                        (LibraryFixtureNetwork(body: #"{"error":"denied"}"#, contentType: "application/json"), 1_024, "未取得 JavaScript")]
        for (network, limit, message) in fixtures {
            let loader = SourceJavaScriptLibraryLoader(network: network,
                limits: .init(maxLibraryBytes: limit))
            let url = URL(string: "https://fixture.invalid/library.js")!
            for _ in 0..<2 {
                switch await loader.load(url) {
                case .success: XCTFail("Non-library response must fail")
                case .failure(let error): XCTAssertTrue(error.displayMessage.contains(message))
                }
            }
            let requests = await network.requests
            XCTAssertEqual(requests.count, 2)
        }
    }

    func testRuntimeLoadsRemoteDependenciesInOrderAndOnlyOnce() throws {
        let context = RuleExecutionContext()
        var requests: [String] = []
        context.libraryProvider = { url in
            requests.append(url.lastPathComponent)
            return .success(url.lastPathComponent == "base.js"
                ? "var libraryCount = (typeof libraryCount === 'undefined' ? 0 : libraryCount) + 1; function base() { return 21; }"
                : "var derived = base() * 2;")
        }
        let runtime = JSCoreRuntime(executionContext: context)
        let manifest = #"{"10":"https://fixture.invalid/base.js","2":"https://fixture.invalid/dependent.js"}"#
        try runtime.preloadJavaScriptLibrary(manifest).get()
        try runtime.preloadJavaScriptLibrary(manifest).get()
        XCTAssertEqual(try runtime.evaluate("derived + ':' + libraryCount").get(), "42:1")
        XCTAssertEqual(requests, ["base.js", "dependent.js"])
    }

    func testDownloadDeadlineReturnsFailureAndCanRetry() async {
        let network = LibraryFixtureNetwork(delay: 500_000_000)
        let loader = SourceJavaScriptLibraryLoader(network: network, limits: .init(timeout: 0.05))
        let url = URL(string: "https://fixture.invalid/library.js")!
        for _ in 0..<2 {
            switch await loader.load(url) {
            case .success: XCTFail("A timed-out library must not be cached as success")
            case .failure(let error): XCTAssertTrue(error.displayMessage.contains("超时"))
            }
        }
        let requests = await network.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testRuntimeDownloadFailureCanRetryWithoutPartialLibrarySideEffects() throws {
        let context = RuleExecutionContext()
        var shouldFail = true
        context.libraryProvider = { url in
            if url.lastPathComponent == "dependent.js", shouldFail { return .failure(.network("fixture offline")) }
            return .success(url.lastPathComponent == "base.js" ? "var effectCount = 1;" : "effectCount += 1;")
        }
        let runtime = JSCoreRuntime(executionContext: context)
        let manifest = #"{"base":"https://fixture.invalid/base.js","dependent":"https://fixture.invalid/dependent.js"}"#
        if case .success = runtime.preloadJavaScriptLibrary(manifest) { XCTFail("Download failure was swallowed") }
        XCTAssertEqual(try runtime.evaluate("typeof effectCount").get(), "undefined")
        shouldFail = false
        try runtime.preloadJavaScriptLibrary(manifest).get()
        XCTAssertEqual(try runtime.evaluate("effectCount").get(), "2")
    }

    func testMissingProviderFailsClearlyAndInlineLibraryStillWorks() throws {
        let runtime = JSCoreRuntime()
        if case .success = runtime.preloadJavaScriptLibrary(#"{"library":"https://fixture.invalid/library.js"}"#) {
            XCTFail("A URL map must not be evaluated as JavaScript")
        }
        try runtime.preloadJavaScriptLibrary("var inlineValue = 42;").get()
        XCTAssertEqual(try runtime.evaluate("inlineValue").get(), "42")
    }
}

private actor LibraryFixtureNetwork: SourceNetworkClient {
    private(set) var requests: [SourceRequest] = []
    let body: String
    let status: Int
    let contentType: String
    let delay: UInt64

    init(body: String = "var fixture = 1;", status: Int = 200,
         contentType: String = "application/javascript", delay: UInt64 = 0) {
        self.body = body
        self.status = status
        self.contentType = contentType
        self.delay = delay
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        requests.append(request)
        if delay > 0 {
            do { try await Task.sleep(nanoseconds: delay) }
            catch { return .failure(.network("fixture cancelled")) }
        }
        return .success(SourceResponse(url: request.url, statusCode: status,
            headers: ["Content-Type": contentType], body: body, data: Data(body.utf8)))
    }
}

private final class LibraryFixtureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant = Date(timeIntervalSince1970: 1_000)
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return instant }
    func advance(_ interval: TimeInterval) { lock.lock(); defer { lock.unlock() }; instant.addTimeInterval(interval) }
}
