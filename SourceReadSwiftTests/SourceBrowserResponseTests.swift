import XCTest
import WebKit
@testable import SourceReadSwift

final class SourceBrowserResponseTests: XCTestCase {
    func testFalseReturnsCurrentDOMURLAndCallableStatusWithoutRefetch() async throws {
        let network = BrowserResponseFixtureNetwork()
        let cookies = SourceCookieStore(storageURL: nil)
        let source = makeSource()
        let engine = LegadoSourceEngine(network: network, cookieStore: cookies, browserLoginProvider: { _, _ in
            Self.page(url: "https://browser.fixture.invalid/result#config=changed", body: "<div id='result-output'>selected</div>")
        })
        _ = try await engine.performLoginInteraction(source: source, action: """
        var response = java.startBrowserAwait(source.bookSourceUrl + '/login', 'Menu', false);
        source.put('html', response.body());
        source.put('url', response.url());
        source.put('original', response.originalUrl());
        source.put('status', response.code());
        source.put('successful', response.isSuccessful());
        """, credentials: [:]).get()
        let state = engine.persistentState(for: source)
        XCTAssertEqual(state.get("source.variable.html"), "<div id='result-output'>selected</div>")
        XCTAssertEqual(state.get("source.variable.url"), "https://browser.fixture.invalid/result#config=changed")
        XCTAssertEqual(state.get("source.variable.original"), "https://browser.fixture.invalid/login")
        XCTAssertEqual(state.get("source.variable.status"), "200")
        XCTAssertEqual(state.get("source.variable.successful"), "true")
        let requests = await network.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testDefaultRefetchUsesNewCookieAndReturnsNetworkBody() async throws {
        let cookies = SourceCookieStore(storageURL: nil)
        let network = BrowserResponseFixtureNetwork()
        let source = makeSource()
        let engine = LegadoSourceEngine(network: network, cookieStore: cookies, browserLoginProvider: { url, _ in
            _ = SourceScriptCookieBridge(store: cookies).perform(.write(url, "session=updated; Path=/"))
            return Self.page(url: "https://browser.fixture.invalid/account", body: "<p>Browser DOM</p>")
        })
        _ = try await engine.performLoginInteraction(source: source, action: """
        var response = java.startBrowserAwait(source.bookSourceUrl + '/login', 'Login');
        source.put('html', response.body());
        source.put('status', response.code());
        """, credentials: [:]).get()
        let requests = await network.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url.path, "/login")
        XCTAssertEqual(requests.first?.headers["Cookie"], "session=updated")
        XCTAssertEqual(engine.persistentState(for: source).get("source.variable.html"), "<p>Refetched document</p>")
        XCTAssertEqual(engine.persistentState(for: source).get("source.variable.status"), "200")
    }

    func testNonSuccessfulBrowserStatusDoesNotBecomeSyntheticLoginSuccess() async throws {
        let source = makeSource()
        let engine = LegadoSourceEngine(cookieStore: SourceCookieStore(storageURL: nil), browserLoginProvider: { _, _ in
            Self.page(url: "https://browser.fixture.invalid/denied", body: "<p>Denied</p>", status: 403)
        })
        _ = try await engine.performLoginInteraction(source: source, action: """
        var response = java.startBrowserAwait(source.bookSourceUrl + '/login', 'Login', false);
        source.put('status', response.code());
        source.put('successful', response.isSuccessful());
        """, credentials: [:]).get()
        XCTAssertEqual(engine.persistentState(for: source).get("source.variable.status"), "403")
        XCTAssertEqual(engine.persistentState(for: source).get("source.variable.successful"), "false")
    }

    func testInlineHTMLMenuReachesBrowserAndReturnsItsEditedDOM() async throws {
        let source = makeSource()
        let engine = LegadoSourceEngine(cookieStore: SourceCookieStore(storageURL: nil), browserLoginProvider: { url, _ in
            XCTAssertEqual(url.scheme, "data")
            let original = try? SourceInlineEnvelope.response(for: url).get()
            XCTAssertEqual(original?.body, "<span id='selection'>old</span>")
            return Self.page(url: url.absoluteString, body: "<span id='selection'>new</span>")
        })
        _ = try await engine.performLoginInteraction(source: source, action: """
        var page = 'data:text/html;base64,' + java.base64Encode("<span id='selection'>old</span>");
        var result = java.startBrowserAwait(page, 'Settings', false);
        source.put('selection', result.body());
        """, credentials: [:]).get()
        XCTAssertEqual(engine.persistentState(for: source).get("source.variable.selection"), "<span id='selection'>new</span>")
    }

    func testBrowserAddressAcceptsOnlyBoundedHTMLAndHTTP() {
        XCTAssertNotNil(SourceLoginBrowserAction.browserPageURL("data:text/html;base64,PGI+eDwvYj4="))
        for address in ["data:application/javascript,alert(1)", "data:text/htmlx,invalid", "file:///private/test.html", "javascript:alert(1)", "data:text/html;base64,invalid!"] {
            XCTAssertNil(SourceLoginBrowserAction.browserPageURL(address))
        }
        XCTAssertNil(SourceLoginBrowserAction.browserPageURL("data:text/html," + String(repeating: "x", count: 524_288)))
    }

    @MainActor
    func testWebKitCaptureReadsEditedDOMInsteadOfOriginalInlineHTML() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = SourceBrowserUserAgent.value
        let loaded = expectation(description: "Local inline menu loaded")
        let delegate = BrowserCaptureNavigation(loaded: loaded)
        webView.navigationDelegate = delegate
        let html = "<html><body><span id='selection'>old</span></body></html>"
        let url = try XCTUnwrap(SourceLoginBrowserAction.browserPageURL("data:text/html;base64," + Data(html.utf8).base64EncodedString()))
        webView.load(URLRequest(url: url))
        await fulfillment(of: [loaded], timeout: 10)
        if let failure = delegate.failure { throw failure }
        let browserAgent = try await webView.evaluateJavaScript("navigator.userAgent") as? String
        let scriptAgent = try JSCoreRuntime().evaluate("java.getWebViewUA()").get()
        XCTAssertEqual(browserAgent, SourceBrowserUserAgent.value)
        XCTAssertEqual(scriptAgent, browserAgent, "Source HTTP rules and the login browser must share their compatibility identity")
        XCTAssertTrue(scriptAgent.contains("Mobile/") && scriptAgent.contains("AppleWebKit/"))
        _ = try await webView.evaluateJavaScript("document.getElementById('selection').textContent = 'chosen';")
        let response = try await SourceBrowserPageCapture.capture(from: webView, statusCode: 200, headers: [:])
        XCTAssertTrue(response.body.contains(">chosen</span>"))
        XCTAssertFalse(response.body.contains(">old</span>"))
        XCTAssertEqual(response.url, url)
        XCTAssertEqual(response.data, Data(response.body.utf8))
    }

    private func makeSource() -> BookSource {
        BookSource(bookSourceName: "Browser response fixture", bookSourceUrl: "https://browser.fixture.invalid",
            loginUi: #"[{"name":"account","type":"text"}]"#)
    }

    private static func page(url: String, body: String, status: Int = 200) -> SourceResponse {
        SourceResponse(url: URL(string: url)!, statusCode: status, headers: [:], body: body, data: Data(body.utf8))
    }
}

private actor BrowserResponseFixtureNetwork: SourceNetworkClient {
    private(set) var requests: [SourceRequest] = []
    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        requests.append(request)
        let body = "<p>Refetched document</p>"
        return .success(SourceResponse(url: request.url, statusCode: 200, headers: [:], body: body, data: Data(body.utf8)))
    }
}

@MainActor
private final class BrowserCaptureNavigation: NSObject, WKNavigationDelegate {
    let loaded: XCTestExpectation
    var failure: Error?
    init(loaded: XCTestExpectation) { self.loaded = loaded }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failure = error
        loaded.fulfill()
    }
}
