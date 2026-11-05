import XCTest
@testable import SourceReadSwift

final class SourceRateLimiterTests: XCTestCase {
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
        switch await cancelled.result {
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
