import XCTest
@testable import SourceReadSwift

final class SourceScriptFreshCookieTests: XCTestCase {
    func testFirstAjaxAfterBrowserCompletionUsesCurrentCookieInsteadOfOldSnapshot() async throws {
        let cookies = SourceCookieStore(storageURL: nil)
        let origin = URL(string: "https://login.fixture.invalid")!
        await cookies.storeSetCookieHeaders(["Set-Cookie": "session=old; Path=/"], for: origin)
        let network = FreshCookieFixtureNetwork()
        let source = makeSource()
        let engine = LegadoSourceEngine(network: network, cookieStore: cookies,
            browserLoginProvider: { url, _ in
                let current = SourceScriptCookieBridge(store: cookies).perform(.write(url, "session=browser-new; Path=/"))
                XCTAssertTrue(current?.contains("session=browser-new") == true)
                return "https://login.fixture.invalid/account"
            })
        engine.persistentState(for: source).put("session=old", for: "cookieHeader")
        _ = try await engine.performLoginInteraction(source: source, action: """
        java.startBrowserAwait('https://login.fixture.invalid/login', 'Login');
        java.ajax('https://login.fixture.invalid/account');
        """, credentials: [:]).get()
        let requests = await network.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(cookieHeader(requests[0]), "session=browser-new")
    }

    func testAutomaticCookieIsResolvedForActualAjaxHostAndNeverLeaksSourceSnapshot() async throws {
        let cookies = SourceCookieStore(storageURL: nil)
        await cookies.storeSetCookieHeaders(["Set-Cookie": "sourceOnly=secret-fixture; Path=/"],
            for: URL(string: "https://login.fixture.invalid")!)
        await cookies.storeSetCookieHeaders(["Set-Cookie": "otherOnly=other-fixture; Path=/"],
            for: URL(string: "https://other.fixture.invalid")!)
        let network = FreshCookieFixtureNetwork()
        let source = makeSource()
        let engine = LegadoSourceEngine(network: network, cookieStore: cookies)
        engine.persistentState(for: source).put("sourceOnly=stale-fixture", for: "cookieHeader")
        _ = try await engine.performLoginInteraction(source: source, action: """
        java.ajax('https://other.fixture.invalid/account');
        java.ajax('https://empty.fixture.invalid/account');
        """, credentials: [:]).get()
        let requests = await network.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(cookieHeader(requests[0]), "otherOnly=other-fixture")
        XCTAssertNil(cookieHeader(requests[1]))
    }

    func testResponseCookieIsStoredBeforeNextAjaxInSameScript() async throws {
        let cookies = SourceCookieStore(storageURL: nil)
        let network = FreshCookieFixtureNetwork()
        let source = makeSource()
        let engine = LegadoSourceEngine(network: network, cookieStore: cookies)
        _ = try await engine.performLoginInteraction(source: source, action: """
        java.ajax('https://login.fixture.invalid/set-cookie');
        java.ajax('https://login.fixture.invalid/account');
        source.put('visibleCookie', android.webkit.CookieManager.getInstance().getCookie(source.bookSourceUrl));
        """, credentials: [:]).get()
        let requests = await network.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertNil(cookieHeader(requests[0]))
        XCTAssertEqual(cookieHeader(requests[1]), "session=network-new")
        XCTAssertEqual(engine.persistentState(for: source).get("source.variable.visibleCookie"), "session=network-new")
    }

    func testAuthorCookieHeadersKeepPriorityOverAutomaticCookieJar() async throws {
        let cookies = SourceCookieStore(storageURL: nil)
        await cookies.storeSetCookieHeaders(["Set-Cookie": "session=automatic; Path=/"],
            for: URL(string: "https://login.fixture.invalid")!)
        let network = FreshCookieFixtureNetwork()
        let source = BookSource(bookSourceName: "Explicit cookie fixture", bookSourceUrl: "https://login.fixture.invalid",
            header: #"{"cOoKiE":"session=author"}"#)
        let first = await Task.detached {
            SynchronousSourceNetworkBridge.loadResult(urlText: "/account", source: source, network: network,
                cookieHeader: "session=stale", persistentValues: ["cookieHeader": "session=stale"], cookieStore: cookies)
        }.value
        _ = try XCTUnwrap(first).get()
        let second = await Task.detached {
            SynchronousSourceNetworkBridge.loadResult(
                urlText: #"https://login.fixture.invalid/account,{"headers":{"COOKIE":"session=per-request"}}"#,
                source: source, network: network, cookieStore: cookies)
        }.value
        _ = try XCTUnwrap(second).get()
        let requests = await network.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(cookieHeader(requests[0]), "session=author")
        XCTAssertEqual(cookieHeader(requests[1]), "session=per-request")
        XCTAssertEqual(requests[1].headers.keys.filter { $0.lowercased() == "cookie" }.count, 1)
    }

    func testLegacyBridgeWithoutCookieStoreKeepsExplicitSnapshotBehavior() async throws {
        let network = FreshCookieFixtureNetwork()
        let source = makeSource()
        let result = await Task.detached {
            SynchronousSourceNetworkBridge.loadResult(urlText: "/account", source: source, network: network,
                cookieHeader: "session=legacy", persistentValues: ["cookieHeader": "session=older"])
        }.value
        _ = try XCTUnwrap(result).get()
        let requests = await network.requests
        XCTAssertEqual(cookieHeader(try XCTUnwrap(requests.first)), "session=legacy")
    }

    private func makeSource() -> BookSource {
        BookSource(bookSourceName: "Fresh script cookies", bookSourceUrl: "https://login.fixture.invalid",
            loginUi: #"[{"name":"account","type":"text"}]"#)
    }

    private func cookieHeader(_ request: SourceRequest) -> String? {
        request.headers.first { $0.key.lowercased() == "cookie" }?.value
    }
}

private actor FreshCookieFixtureNetwork: SourceNetworkClient {
    private(set) var requests: [SourceRequest] = []

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        requests.append(request)
        let headers = request.url.path == "/set-cookie"
            ? ["Set-Cookie": "session=network-new; Path=/; HttpOnly"] : [:]
        return .success(SourceResponse(url: request.url, statusCode: 200, headers: headers,
            body: "ok", data: Data("ok".utf8)))
    }
}
