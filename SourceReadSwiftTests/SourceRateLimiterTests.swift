import XCTest
@testable import SourceReadSwift

final class SourceRateLimiterTests: XCTestCase {
    func testEngineTransportRetriesConsumeTheirOwnRatePermit() async throws {
        for rate in ["120", "1/120"] {
            let network = SourceRetryFixtureNetwork(firstFailure: .network("Synthetic offline response"))
            let engine = LegadoSourceEngine(network: network, cookieStore: SourceCookieStore(storageURL: nil))
            engine.allowWebViewFallback = false
            let source = makeRetrySource(rate: rate)
            _ = try await engine.searchBooks(source: source, keyword: "fixture", page: 1).get()
            let starts = await network.starts
            XCTAssertEqual(starts.count, 2)
            guard starts.count == 2 else { continue }
            XCTAssertGreaterThanOrEqual(Double(starts[1] - starts[0]) / 1_000_000, 80, rate)
        }
    }

    func testEngineDoesNotReplayBlockedFailuresOrHTTPRateLimits() async throws {
        for network in [SourceRetryFixtureNetwork(firstFailure: .blocked("等待一分钟后重试")),
                        SourceRetryFixtureNetwork(firstFailure: .network("HTTP 429")),
                        SourceRetryFixtureNetwork(firstFailure: .network("访问过快，请稍后重试")),
                        SourceRetryFixtureNetwork(statusCode: 429)] {
            let engine = LegadoSourceEngine(network: network, cookieStore: SourceCookieStore(storageURL: nil))
            engine.allowWebViewFallback = false
            guard case .failure = await engine.searchBooks(source: makeRetrySource(rate: nil), keyword: "fixture", page: 1) else {
                return XCTFail("Blocked response must remain a failure")
            }
            let starts = await network.starts
            XCTAssertEqual(starts.count, 1)
        }
    }

    func testSourceWebViewFallbackCannotReplayAnExplicitBlockOrHTTPRateLimit() async {
        let fixtures: [(SourceRetryFixtureNetwork, SourceEngineError)] = [
            (SourceRetryFixtureNetwork(firstFailure: .blocked("等待一分钟后重试")), .blocked("等待一分钟后重试")),
            (SourceRetryFixtureNetwork(firstFailure: .network("HTTP 429")), .network("HTTP 429")),
            (SourceRetryFixtureNetwork(statusCode: 429, body: ""), .network("HTTP 429"))
        ]
        for (network, expected) in fixtures {
            let engine = LegadoSourceEngine(network: network, cookieStore: SourceCookieStore(storageURL: nil))
            let source = BookSource(bookSourceName: "WebView rate limit fixture",
                bookSourceUrl: "https://webview-rate.fixture.invalid", searchUrl: #"/search,{"retry":1}"#,
                ruleSearch: .init(fields: ["bookList": "$.books", "name": "name", "bookUrl": "url"]),
                raw: ["webView": "true"])
            let result = await engine.searchBooks(source: source, keyword: "fixture", page: 1)
            guard case .failure(let error) = result else { return XCTFail("Expected original source block") }
            XCTAssertEqual(error, expected)
            let starts = await network.starts
            XCTAssertEqual(starts.count, 1)
        }
    }

    private func makeRetrySource(rate: String?) -> BookSource {
        BookSource(bookSourceName: "Retry fixture", bookSourceUrl: "https://retry-\(UUID().uuidString).fixture.invalid",
            searchUrl: #"/search,{"retry":1}"#,
            ruleSearch: .init(fields: ["bookList": "$.books", "name": "name", "bookUrl": "url"]),
            raw: rate.map { ["concurrentRate": $0] } ?? [:])
    }

    func testParsesIntervalMode() {
        let rule = SourceRateRule("500")
        XCTAssertEqual(rule?.limit, 1)
        XCTAssertEqual(rule?.windowNanoseconds, 500_000_000)
        XCTAssertEqual(rule?.isWindowed, false)
        XCTAssertEqual(rule?.rawValue, "500")
    }

    func testParsesWindowMode() {
        let rule = SourceRateRule("3/1000")
        XCTAssertEqual(rule?.limit, 3)
        XCTAssertEqual(rule?.windowNanoseconds, 1_000_000_000)
        XCTAssertEqual(rule?.isWindowed, true)
    }

    func testRejectsUnlimitedAndGarbage() {
        XCTAssertNil(SourceRateRule(nil))
        XCTAssertNil(SourceRateRule(""))
        XCTAssertNil(SourceRateRule("0"))
        XCTAssertNil(SourceRateRule("abc"))
        XCTAssertNil(SourceRateRule("3/0"))
        XCTAssertNil(SourceRateRule("0/1000"))
        XCTAssertNil(SourceRateRule("-5"))
    }

    func testRequestCarriesSourceRate() {
        let source = BookSource(
            bookSourceName: "rate-test",
            bookSourceUrl: "https://example.com",
            raw: ["concurrentRate": "250"]
        )
        XCTAssertEqual(source.concurrentRate, "250")
        let request = SourceRequestBuilder().buildPageRequest(
            source: source,
            urlText: "https://example.com/"
        )
        XCTAssertEqual(request.concurrentRate, "250")
        XCTAssertEqual(request.rateLimitKey, "https://example.com")
    }

    func testIntervalModeWaitsBetweenRequests() async throws {
        let limiter = SourceRateLimiter()
        guard let rule = SourceRateRule("120") else { return XCTFail("rule") }
        try await limiter.acquire(key: "interval", rule: rule)
        limiter.release(key: "interval", rule: rule)

        let start = DispatchTime.now().uptimeNanoseconds
        try await limiter.acquire(key: "interval", rule: rule)
        limiter.release(key: "interval", rule: rule)
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        XCTAssertGreaterThanOrEqual(elapsedMs, 80)
    }

    func testWindowModeBlocksBeyondLimit() async throws {
        let limiter = SourceRateLimiter()
        guard let rule = SourceRateRule("2/200") else { return XCTFail("rule") }
        try await limiter.acquire(key: "window", rule: rule)
        try await limiter.acquire(key: "window", rule: rule)

        let start = DispatchTime.now().uptimeNanoseconds
        try await limiter.acquire(key: "window", rule: rule)
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        XCTAssertGreaterThanOrEqual(elapsedMs, 150)
    }

    func testCancelledWaiterCannotReleaseTheActiveRequestsPermit() async throws {
        let limiter = SourceRateLimiter()
        let rule = try XCTUnwrap(SourceRateRule("10"))
        try await limiter.acquire(key: "held", rule: rule)
        let cancelled = Task {
            try await limiter.acquire(key: "held", rule: rule)
            defer { limiter.release(key: "held", rule: rule) }
            XCTFail("A cancelled waiter must not enter the request or release another request's permit")
        }
        cancelled.cancel()
        let cancellationResult = await cancelled.result
        switch cancellationResult {
        case .success: XCTFail("Expected CancellationError while waiting for a permit")
        case .failure(let error): XCTAssertTrue(error is CancellationError)
        }

        let entered = expectation(description: "The first request still owns the permit")
        entered.isInverted = true
        let next = Task {
            try await limiter.acquire(key: "held", rule: rule)
            defer { limiter.release(key: "held", rule: rule) }
            entered.fulfill()
        }
        await fulfillment(of: [entered], timeout: 0.05)
        next.cancel()
        _ = await next.result
        limiter.release(key: "held", rule: rule)
        try await limiter.acquire(key: "held", rule: rule)
        limiter.release(key: "held", rule: rule)
    }
}

private actor SourceRetryFixtureNetwork: SourceNetworkClient {
    private let firstFailure: SourceEngineError?
    private let statusCode: Int
    private let body: String
    private(set) var starts: [UInt64] = []

    init(firstFailure: SourceEngineError? = nil, statusCode: Int = 200,
         body: String = #"{"books":[{"name":"Fixture","url":"/book/1"}]}"#) {
        self.firstFailure = firstFailure
        self.statusCode = statusCode
        self.body = body
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        starts.append(DispatchTime.now().uptimeNanoseconds)
        if starts.count == 1, let firstFailure { return .failure(firstFailure) }
        return .success(SourceResponse(url: request.url, statusCode: statusCode,
            headers: ["Content-Type": "application/json"], body: body, data: Data(body.utf8)))
    }
}
