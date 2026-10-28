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

    func testIntervalModeWaitsBetweenRequests() async {
        let limiter = SourceRateLimiter()
        guard let rule = SourceRateRule("120") else { return XCTFail("rule") }
        await limiter.acquire(key: "interval", rule: rule)
        limiter.release(key: "interval", rule: rule)

        let start = DispatchTime.now().uptimeNanoseconds
        await limiter.acquire(key: "interval", rule: rule)
        limiter.release(key: "interval", rule: rule)
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        XCTAssertGreaterThanOrEqual(elapsedMs, 80)
    }

    func testWindowModeBlocksBeyondLimit() async {
        let limiter = SourceRateLimiter()
        guard let rule = SourceRateRule("2/200") else { return XCTFail("rule") }
        await limiter.acquire(key: "window", rule: rule)
        await limiter.acquire(key: "window", rule: rule)

        let start = DispatchTime.now().uptimeNanoseconds
        await limiter.acquire(key: "window", rule: rule)
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        XCTAssertGreaterThanOrEqual(elapsedMs, 150)
    }
}