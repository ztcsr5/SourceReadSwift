import XCTest
@testable import SourceReadSwift

final class SourceCookieStoreTests: XCTestCase {
    func testPersistentCookieRoundTripPreservesHTTPOnlyAndSecureAttributes() async throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: location) }
        let url = try XCTUnwrap(URL(string: "https://cookie.fixture.invalid/account"))
        let cookie = try XCTUnwrap(HTTPCookie.cookies(withResponseHeaderFields: [
            "Set-Cookie": "session=fixture; Path=/account; Secure; HttpOnly"
        ], for: url).first)
        XCTAssertTrue(cookie.isHTTPOnly)
        await SourceCookieStore(storageURL: location).store([cookie], for: url)
        let restored = await SourceCookieStore(storageURL: location).cookies(for: url)
        let persisted = try XCTUnwrap(restored.first)
        XCTAssertTrue(persisted.isHTTPOnly, "Disk restoration must not expose a server-only cookie to script")
        XCTAssertTrue(persisted.isSecure)
        XCTAssertEqual(persisted.path, "/account")
    }

    func testSecureCookieNeverLeavesHTTPSAndStillMatchesPathAndDomain() async throws {
        let store = SourceCookieStore(storageURL: nil)
        let origin = URL(string: "https://cookie.fixture.invalid/account/login")!
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .name: "session", .value: "fixture", .domain: ".fixture.invalid",
            .path: "/account", .secure: "TRUE"
        ]))
        XCTAssertTrue(cookie.isSecure)
        await store.storeWebViewCookies([cookie])
        let secure = await store.cookieHeader(for: origin)
        let insecure = await store.cookieHeader(for: URL(string: "http://cookie.fixture.invalid/account/read")!)
        let siblingPath = await store.cookieHeader(for: URL(string: "https://cookie.fixture.invalid/accounts")!)
        let unrelated = await store.cookieHeader(for: URL(string: "https://notfixture.invalid/account")!)
        XCTAssertEqual(secure, "session=fixture")
        XCTAssertNil(insecure)
        XCTAssertNil(siblingPath)
        XCTAssertNil(unrelated)
    }

    func testNonSecureCookieStillSupportsExplicitHTTPSource() async throws {
        let store = SourceCookieStore(storageURL: nil)
        let origin = URL(string: "http://cookie.fixture.invalid/read")!
        await store.storeSetCookieHeaders(["Set-Cookie": "legacy=fixture; Path=/"], for: origin)
        let header = await store.cookieHeader(for: origin)
        XCTAssertEqual(header, "legacy=fixture")
    }

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

    func testCookieSetOnParentDomainReachesSubdomain() async throws {
        let store = SourceCookieStore(storageURL: nil)
        let loginURL = URL(string: "https://example.com/login")!
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: [
            "Set-Cookie": "sid=parent; Path=/; Domain=.example.com"
        ], for: loginURL)

        await store.storeWebViewCookies(cookies)
        let header = await store.cookieHeader(for: URL(string: "https://www.example.com/api/search")!)

        XCTAssertEqual(header, "sid=parent")
    }

    func testNonRFCExpiryDateStillExpires() async throws {
        let store = SourceCookieStore(storageURL: nil)
        let url = URL(string: "http://www.tianyu8.org/searchde.html")!
        await store.storeSetCookieHeaders(
            ["Set-Cookie": "ss_search_delay=1; expires=Thu, 29-Oct-2026 17:10:52 GMT; Max-Age=30; path=/"],
            for: url
        )
        let cookies = await store.allCookies()
        XCTAssertEqual(cookies.count, 1)
        let expiry = try XCTUnwrap(cookies.first?.expiresDate)
        XCTAssertGreaterThan(expiry, Date())
        XCTAssertLessThan(expiry, Date().addingTimeInterval(120))
    }

    func testExpiredMaxAgeCookieIsNotSent() async throws {
        let store = SourceCookieStore(storageURL: nil)
        let url = URL(string: "http://www.tianyu8.org/searchde.html")!
        await store.storeSetCookieHeaders(
            ["Set-Cookie": "ss_search_delay=1; Max-Age=0; path=/"],
            for: url
        )
        let header = await store.cookieHeader(for: url)
        XCTAssertNil(header)
    }

    func testCooldownPageDetection() {
        let page = "\n\n\n<script>alert(\"搜索间隔: 30 秒\");window.history.go(-1);</script>"
        XCTAssertTrue(URLSessionSourceNetworkClient.looksLikeCooldownPage(page))
        XCTAssertFalse(URLSessionSourceNetworkClient.looksLikeCooldownPage("<html>" + String(repeating: "x", count: 800) + "alert(间隔)</html>"))
    }

    /// The real kill-and-relaunch path: a fresh process builds a new store from
    /// the same file, and the login cookie must still be sent on the next request.
    /// Without this, an app restart looked logged-out while the disk file existed.
    func testCookieSurvivesRelaunchThroughTheDefaultDiskStore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let location = directory.appendingPathComponent("cookies.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let loginURL = URL(string: "https://relaunch.fixture.invalid/login")!
        let firstProcess = SourceCookieStore(storageURL: location)
        await firstProcess.storeSetCookieHeaders(
            ["Set-Cookie": "remember=me; Path=/; Domain=relaunch.fixture.invalid; HttpOnly"],
            for: loginURL)
        let storedCount = await firstProcess.cookieCount()
        XCTAssertEqual(storedCount, 1)

        let relaunched = SourceCookieStore(storageURL: location)
        let contentURL = URL(string: "https://relaunch.fixture.invalid/read/42")!
        let header = await relaunched.cookieHeader(for: contentURL)
        XCTAssertEqual(header, "remember=me", "Relaunch must reuse the persisted login cookie")
        let cookies = await relaunched.allCookies()
        XCTAssertEqual(cookies.count, 1)
        XCTAssertTrue(cookies[0].isHTTPOnly)
        let hosts = await relaunched.hostsWithCookies()
        XCTAssertEqual(hosts, ["relaunch.fixture.invalid"])
        // Asserting the persisted record rather than the memory cache: the file is
        // what the next process reads.
        let data = try Data(contentsOf: location)
        let records = try JSONDecoder().decode([String: [StoredCookieRecord]].self, from: data)
        XCTAssertEqual(records["relaunch.fixture.invalid"]?.first?.name, "remember")
    }

    /// A cleared session must stay cleared after relaunch, otherwise clearing
    /// cookies in the UI silently logs the user back in on next start.
    func testClearedCookiesStayClearedAfterRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let location = directory.appendingPathComponent("cookies.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = URL(string: "https://logout.fixture.invalid/")!
        let store = SourceCookieStore(storageURL: location)
        await store.storeSetCookieHeaders(["Set-Cookie": "session=bye; Path=/"], for: url)
        await store.clearAllCookies()

        let relaunched = SourceCookieStore(storageURL: location)
        let header = await relaunched.cookieHeader(for: url)
        XCTAssertNil(header)
        let remaining = await relaunched.cookieCount()
        XCTAssertEqual(remaining, 0)
    }

    func testCookieStoredOnSubdomainAlsoServesThatSubdomain() async throws {
        let store = SourceCookieStore(storageURL: nil)
        let apiURL = URL(string: "https://m.example.com/api")!
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: [
            "Set-Cookie": "token=sub; Path=/; Domain=m.example.com"
        ], for: apiURL)

        await store.store(cookies, for: apiURL)
        let header = await store.cookieHeader(for: URL(string: "https://m.example.com/read/1")!)

        XCTAssertEqual(header, "token=sub")
    }
}
