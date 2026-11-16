import XCTest
@testable import SourceReadSwift

/// Exercises explicit script cookies through the same jar used by top-level requests.
final class SourceAuthoredCookieTests: XCTestCase {
    func testJavaPutCookieFeedsSearchAndDoesNotLeakToAnotherHost() async throws {
        let cookies = SourceCookieStore(storageURL: nil)
        let network = AuthoredCookieFixtureNetwork()
        let engine = LegadoSourceEngine(network: network, cookieStore: cookies)
        let source = makeSource(searchScript: "java.put('cookieHeader', 'session=authored'); '/search';")
        _ = try await engine.searchBooks(source: source, keyword: "fixture", page: 1).get()
        let stored = await cookies.cookieHeader(for: origin)
        let unrelated = await cookies.cookieHeader(for: otherOrigin)
        XCTAssertEqual(stored, "session=authored")
        XCTAssertNil(unrelated)
        let requests = await network.requests
        XCTAssertEqual(requests.first?.headers["Cookie"], "session=authored")
    }

    func testDirectAssignmentFeedsTopLevelSearch() async throws {
        let cookies = SourceCookieStore(storageURL: nil)
        let network = AuthoredCookieFixtureNetwork()
        let engine = LegadoSourceEngine(network: network, cookieStore: cookies)
        let source = makeSource(searchScript: "cookieHeader = 'session=direct'; '/search';")
        _ = try await engine.searchBooks(source: source, keyword: "fixture", page: 1).get()
        let requests = await network.requests
        XCTAssertEqual(requests.first?.headers["Cookie"], "session=direct")
        let stored = await cookies.cookieHeader(for: origin)
        XCTAssertEqual(stored, "session=direct")
    }

    func testDirectAssignmentFeedsAjaxBeforeTheRuleReturns() async throws {
        let cookies = SourceCookieStore(storageURL: nil)
        let network = AuthoredCookieFixtureNetwork()
        let engine = LegadoSourceEngine(network: network, cookieStore: cookies)
        _ = try await engine.performLoginInteraction(source: makeSource(), action: """
        cookieHeader = 'session=direct';
        java.ajax('https://author.fixture.invalid/account');
        """, credentials: [:]).get()
        let requests = await network.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.headers["Cookie"], "session=direct")
    }

    func testExplicitEmptyAssignmentClearsJarBeforeTheNextAjax() async throws {
        let cookies = SourceCookieStore(storageURL: nil)
        await cookies.storeSetCookieHeaders(["Set-Cookie": "session=old; Path=/"], for: origin)
        let network = AuthoredCookieFixtureNetwork()
        let engine = LegadoSourceEngine(network: network, cookieStore: cookies)
        _ = try await engine.performLoginInteraction(source: makeSource(), action: """
        cookieHeader = '';
        java.ajax('https://author.fixture.invalid/account');
        """, credentials: [:]).get()
        let requests = await network.requests
        XCTAssertNil(requests.first?.headers["Cookie"])
        let stored = await cookies.cookieHeader(for: origin)
        XCTAssertNil(stored)
    }

    func testJavaPutUsesCurrentScriptBaseURL() async throws {
        let cookies = SourceCookieStore(storageURL: nil)
        let network = AuthoredCookieFixtureNetwork()
        let engine = LegadoSourceEngine(network: network, cookieStore: cookies)
        _ = try await engine.performLoginInteraction(source: makeSource(), action: """
        baseUrl = 'https://other.fixture.invalid/account';
        java.put('cookieHeader', 'session=other');
        java.ajax('https://other.fixture.invalid/account');
        """, credentials: [:]).get()
        let requests = await network.requests
        XCTAssertEqual(requests.first?.headers["Cookie"], "session=other")
        let sourceCookie = await cookies.cookieHeader(for: origin)
        XCTAssertNil(sourceCookie)
    }

    func testDirectLogoutAfterNativeWriteInSameScriptDoesNotRestoreItsCookie() async throws {
        for write in ["java.put('cookieHeader', 'session=written');",
                      "cookie.setCookie('https://author.fixture.invalid', 'session=written');"] {
            let cookies = SourceCookieStore(storageURL: nil)
            let network = AuthoredCookieFixtureNetwork()
            let engine = LegadoSourceEngine(network: network, cookieStore: cookies)
            _ = try await engine.performLoginInteraction(source: makeSource(), action: write + """
            cookieHeader = '';
            java.ajax('https://author.fixture.invalid/account');
            """, credentials: [:]).get()
            let requests = await network.requests
            XCTAssertEqual(requests.count, 1)
            XCTAssertNil(requests.first?.headers["Cookie"])
            let stored = await cookies.cookieHeader(for: origin)
            XCTAssertNil(stored)
        }
    }

    func testCookieAPIForAnotherHostDoesNotReplayItsMergedHeaderIntoSourceHost() async throws {
        let cookies = SourceCookieStore(storageURL: nil)
        await cookies.storeSetCookieHeaders(["Set-Cookie": "existing=other; Path=/"], for: otherOrigin)
        let network = AuthoredCookieFixtureNetwork()
        let engine = LegadoSourceEngine(network: network, cookieStore: cookies)
        _ = try await engine.performLoginInteraction(source: makeSource(), action: """
        cookie.setCookie('https://other.fixture.invalid/account', 'session=other');
        java.ajax('https://author.fixture.invalid/account');
        """, credentials: [:]).get()
        let requests = await network.requests
        XCTAssertNil(requests.first?.headers["Cookie"])
        let sourceCookie = await cookies.cookieHeader(for: origin)
        XCTAssertNil(sourceCookie)
        let otherCookie = await cookies.cookieHeader(for: otherOrigin) ?? ""
        XCTAssertTrue(otherCookie.contains("existing=other"))
        XCTAssertTrue(otherCookie.contains("session=other"))
    }

    func testCrossHostResponseCookieIsNotReplayedIntoSourceHost() async throws {
        let cookies = SourceCookieStore(storageURL: nil)
        let network = AuthoredCookieFixtureNetwork()
        let engine = LegadoSourceEngine(network: network, cookieStore: cookies)
        _ = try await engine.performLoginInteraction(source: makeSource(), action: """
        java.ajax('https://other.fixture.invalid/set-cookie');
        java.ajax('https://author.fixture.invalid/account');
        """, credentials: [:]).get()
        let requests = await network.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertNil(requests.last?.headers["Cookie"])
        let sourceCookie = await cookies.cookieHeader(for: origin)
        let otherCookie = await cookies.cookieHeader(for: otherOrigin)
        XCTAssertNil(sourceCookie)
        XCTAssertEqual(otherCookie, "session=response")
    }

    private var origin: URL { URL(string: "https://author.fixture.invalid")! }
    private var otherOrigin: URL { URL(string: "https://other.fixture.invalid")! }

    private func makeSource(searchScript: String = "'/search';") -> BookSource {
        BookSource(bookSourceName: "Authored cookie fixture", bookSourceUrl: origin.absoluteString,
            searchUrl: "@js:" + searchScript,
            ruleSearch: SourceRule(fields: ["bookList": "$.books[*]", "name": "$.name", "bookUrl": "$.url"]),
            loginUi: #"[{"name":"account","type":"text"}]"#)
    }
}

private actor AuthoredCookieFixtureNetwork: SourceNetworkClient {
    private(set) var requests: [SourceRequest] = []

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        requests.append(request)
        let body = request.url.path == "/search"
            ? #"{"books":[{"name":"Fixture book","url":"/book"}]}"# : "ok"
        let headers = request.url.path == "/set-cookie" ? ["Set-Cookie": "session=response; Path=/"] : [:]
        return .success(SourceResponse(url: request.url, statusCode: 200, headers: headers,
            body: body, data: Data(body.utf8)))
    }
}
