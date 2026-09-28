import XCTest
@testable import SourceReadSwift

final class SourceCookieStoreTests: XCTestCase {
    func testCookieHeaderRoundTrip() async throws {
        let store = SourceCookieStore(storageURL: nil)
        let url = URL(string: "https://example.com/path")!
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: [
            "Set-Cookie": "sid=abc; Path=/; Domain=example.com"
        ], for: url)

        await store.store(cookies, for: url)
        let header = await store.cookieHeader(for: url)

        XCTAssertEqual(header, "sid=abc")
    }

    func testStoreWebViewCookiesUsesCookieDomain() async throws {
        let store = SourceCookieStore(storageURL: nil)
        let url = URL(string: "https://example.com/path")!
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: [
            "Set-Cookie": "cf_clearance=ok; Path=/; Domain=example.com"
        ], for: url)

        await store.storeWebViewCookies(cookies)
        let header = await store.cookieHeader(for: url)

        XCTAssertEqual(header, "cf_clearance=ok")
    }

    func testPersistentDiskRoundTrip() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let store1 = SourceCookieStore(storageURL: tempURL)
        let url = URL(string: "https://novel.test/api")!
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: [
            "Set-Cookie": "token=xyz123; Path=/; Domain=novel.test"
        ], for: url)

        await store1.store(cookies, for: url)
        let count1 = await store1.cookieCount()
        XCTAssertEqual(count1, 1)

        // Instantiate fresh store with same file URL
        let store2 = SourceCookieStore(storageURL: tempURL)
        let header2 = await store2.cookieHeader(for: url)
        XCTAssertEqual(header2, "token=xyz123")
        let hosts = await store2.hostsWithCookies()
        XCTAssertEqual(hosts, ["novel.test"])

        // Test clear
        await store2.clearCookies(for: "novel.test")
        let countAfterClear = await store2.cookieCount()
        XCTAssertEqual(countAfterClear, 0)
    }

    func testPruningExpiredCookies() async throws {
        let store = SourceCookieStore(storageURL: nil)
        let url = URL(string: "https://expired.test/api")!
        // Expired cookie in the past (1970)
        let expiredCookie = HTTPCookie(properties: [
            .name: "old_session",
            .value: "expired_val",
            .domain: "expired.test",
            .path: "/",
            .expires: Date(timeIntervalSince1970: 100)
        ])!

        await store.store([expiredCookie], for: url)
        let header = await store.cookieHeader(for: url)
        XCTAssertNil(header)
        let count = await store.cookieCount()
        XCTAssertEqual(count, 0)
    }
}
