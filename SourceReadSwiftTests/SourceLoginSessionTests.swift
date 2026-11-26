import XCTest
import WebKit
@testable import SourceReadSwift

final class SourceLoginSessionTests: XCTestCase {
    @MainActor
    func testNavigationFailureCannotBeOverwrittenByPendingCookieSynchronization() async throws {
        for isProvisional in [false, true] {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let browser = WKWebView(frame: .zero, configuration: configuration)
            var statuses: [String] = []
            var completedPages: [URL?] = []
            var failures = 0
            let coordinator = SourceLoginWebView.Coordinator(
                cookieStore: SourceCookieStore(storageURL: nil), cookieScope: SourceLoginCookieScope(),
                onPageLoaded: { completedPages.append($0) }, onResponse: { _, _ in },
                onStatus: { statuses.append($0) })
            coordinator.onFailure = { _ in failures += 1 }
            coordinator.webView(browser, didStartProvisionalNavigation: nil)
            coordinator.webView(browser, didFinish: nil)
            let synchronization = try XCTUnwrap(coordinator.synchronizationTask)
            let error = URLError(.timedOut)
            if isProvisional { coordinator.webView(browser, didFailProvisionalNavigation: nil, withError: error) }
            else { coordinator.webView(browser, didFail: nil, withError: error) }
            await synchronization.value
            XCTAssertTrue(synchronization.isCancelled)
            XCTAssertNil(coordinator.synchronizationTask)
            coordinator.webView(browser, didFinish: nil)
            XCTAssertNil(coordinator.synchronizationTask, "A late finish callback must not revive a failed page")
            XCTAssertTrue(statuses.last?.hasPrefix("页面加载失败：") == true)
            XCTAssertFalse(statuses.contains { $0.hasPrefix("页面已加载") })
            XCTAssertNil(completedPages.last ?? nil)
            XCTAssertEqual(failures, 1)
        }
    }

    @MainActor
    func testReplacedNavigationCancellationDoesNotReportCurrentPageAsFailed() {
        let browser = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        var statuses: [String] = []
        var failures = 0
        let coordinator = SourceLoginWebView.Coordinator(
            cookieStore: SourceCookieStore(storageURL: nil), cookieScope: SourceLoginCookieScope(),
            onPageLoaded: { _ in }, onResponse: { _, _ in }, onStatus: { statuses.append($0) })
        coordinator.onFailure = { _ in failures += 1 }
        coordinator.webView(browser, didStartProvisionalNavigation: nil)
        coordinator.webView(browser, didFail: nil, withError: URLError(.cancelled))
        coordinator.webView(browser, didFailProvisionalNavigation: nil, withError: URLError(.cancelled))
        XCTAssertEqual(statuses, ["正在加载…"])
        XCTAssertEqual(failures, 0)
    }

    func testCookieWriteFailureCannotReportVerifiedLoginOrActionWithoutWarning() async throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("blocked".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let cookies = SourceCookieStore(storageURL: blocker.appendingPathComponent("cookies.json"))
        let engine = LegadoSourceEngine(cookieStore: cookies)
        let source = BookSource(bookSourceName: "Cookie save failure", bookSourceUrl: "https://failed-login.fixture.invalid",
            loginUrl: "cookie.setCookie(source.bookSourceUrl, 'session=fixture; Path=/');",
            loginCheckJs: "true", loginUi: #"[{"name":"account","type":"text"}]"#)
        let verification = try await engine.login(source: source, credentials: ["account": "fixture"]).get()
        XCTAssertEqual(verification.status, .warning)
        XCTAssertTrue(verification.message.contains("保存失败"))
        let interaction = try await engine.performLoginInteraction(source: source, action: "'done'", credentials: [:]).get()
        XCTAssertTrue(interaction.persistenceWarning?.contains("保存失败") == true)
    }

    @MainActor
    func testWebKitLoginCookieReachesTheEngineAfterBrowserSynchronization() async throws {
        let cookies = SourceCookieStore(storageURL: nil)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let browser = WKWebView(frame: .zero, configuration: configuration)
        let origin = URL(string: "https://web-login.fixture.invalid/")!
        let cookie = try XCTUnwrap(HTTPCookie.cookies(withResponseHeaderFields:
            ["Set-Cookie": "reader.token=browser-fixture; Path=/; HttpOnly; Secure"], for: origin).first)
        defer { HTTPCookieStorage.shared.deleteCookie(cookie) }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { continuation.resume() }
        }
        let count = await SourceLoginBrowserCookies.synchronize(from: browser, into: cookies)
        XCTAssertEqual(count, 1)
        let source = BookSource(bookSourceName: "WebKit login fixture", bookSourceUrl: origin.absoluteString,
            loginUi: #"[{"name":"cookie","type":"text"}]"#)
        let engine = LegadoSourceEngine(cookieStore: cookies)
        let fields = try await engine.performLoginAction(source: source,
            action: "java.upLoginData({cookie: android.webkit.CookieManager.getInstance().getCookie(source.bookSourceUrl)})",
            credentials: [:]).get()
        XCTAssertEqual(fields.first?.defaultValue, "reader.token=browser-fixture")
    }

    func testBrowserCompletionContinuesTheSameNativeScriptOnceAndCancellationDoesNot() async throws {
        let source = BookSource(bookSourceName: "Awaited session", bookSourceUrl: "https://login.fixture.invalid",
            loginUrl: """
            function signIn() {
                source.put('attempts', String(Number(source.get('attempts') || 0) + 1));
                var response = java.startBrowserAwait(source.bookSourceUrl + '/login', 'Fixture login', false);
                source.put('completedURL', response.url());
                source.put('completedBody', response.body());
                source.put('completedCode', response.code());
                java.upLoginData({account: 'fixture-user'});
            }
            """, loginUi: #"[{"name":"account","type":"text"}]"#)
        let engine = LegadoSourceEngine(cookieStore: SourceCookieStore(storageURL: nil), browserLoginProvider: { url, title in
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertEqual(url.path, "/login")
            XCTAssertEqual(title, "Fixture login")
            return SourceResponse(url: URL(string: "https://login.fixture.invalid/account")!, statusCode: 200,
                headers: [:], body: "<p>Account ready</p>", data: Data("<p>Account ready</p>".utf8))
        })
        let result = try await engine.performLoginInteraction(source: source, action: "signIn()", credentials: [:]).get()
        XCTAssertNil(result.destination)
        XCTAssertEqual(result.fields.first?.defaultValue, "fixture-user")
        XCTAssertEqual(engine.persistentState(for: source).get("source.variable.attempts"), "1")
        XCTAssertEqual(engine.persistentState(for: source).get("source.variable.completedURL"), "https://login.fixture.invalid/account")
        XCTAssertEqual(engine.persistentState(for: source).get("source.variable.completedBody"), "<p>Account ready</p>")
        XCTAssertEqual(engine.persistentState(for: source).get("source.variable.completedCode"), "200")

        let cancelled = LegadoSourceEngine(cookieStore: SourceCookieStore(storageURL: nil), browserLoginProvider: { _, _ in nil })
        if case .success = await cancelled.performLoginInteraction(source: source, action: "signIn()", credentials: [:]) {
            XCTFail("Cancelled web login cannot continue as success")
        }
        XCTAssertEqual(cancelled.persistentState(for: source).get("source.variable.attempts"), "1")
        XCTAssertTrue(cancelled.persistentState(for: source).get("source.variable.completedURL").isEmpty)
    }

    func testAndroidCookieManagerAndLoginUpdatesSurviveRelaunchAndClearOnLogout() async throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: location) }
        let secrets = LoginSessionSecrets()
        let variableStore = SourceVariableStore(secrets: secrets)
        let cookies = SourceCookieStore(storageURL: location)
        let source = BookSource(bookSourceName: "Aggregate session", bookSourceUrl: "https://login.fixture.invalid",
            searchUrl: "https://login.fixture.invalid/search?q={{key}}",
            ruleSearch: SourceRule(fields: ["bookList": "$.books", "name": "name", "bookUrl": "url"]),
            loginUrl: """
            function login() {
                var cookies = android.webkit.CookieManager.getInstance();
                cookies.setCookie(source.bookSourceUrl, 'reader.token=fixture-session; Path=/; Max-Age=3600');
                cookies.flush();
                var restored = Packages.android.webkit.CookieManager.getInstance().getCookie(source.bookSourceUrl);
                if (restored.indexOf('reader.token=fixture-session') < 0) throw new Error('Cookie was not saved');
                var fields = new Packages.java.util.HashMap();
                fields.put('account', 'fixture-user');
                java.upLoginData(fields);
                source.putLoginHeader({'X-Reader-Token': 'fixture-header'});
            }
            function logout() {
                cookie.removeCookie(source.bookSourceUrl);
                source.removeLoginHeader();
                source.removeLoginInfo();
            }
            """, loginUi: #"[{"name":"account","type":"text"}]"#)
        let first = LegadoSourceEngine(cookieStore: cookies, sourceVariables: variableStore)
        _ = try await first.performLoginAction(source: source, action: "login()", credentials: [:]).get()

        let restoredCookies = SourceCookieStore(storageURL: location)
        let network = SessionRequestFixture(cookies: restoredCookies)
        let restarted = LegadoSourceEngine(network: network, cookieStore: restoredCookies, sourceVariables: variableStore)
        let fields = try await restarted.loginFields(source: source).get()
        XCTAssertEqual(fields.first?.defaultValue, "fixture-user")
        let books = try await restarted.searchBooks(source: source, keyword: "fixture", page: 1).get()
        XCTAssertEqual(books.first?.name, "Authenticated fixture")
        let sent = await network.lastAuthorization
        XCTAssertEqual(sent, "fixture-header")

        _ = try await restarted.performLoginAction(source: source, action: "logout()", credentials: [:]).get()
        let afterLogout = LegadoSourceEngine(cookieStore: SourceCookieStore(storageURL: location), sourceVariables: variableStore)
        XCTAssertFalse(afterLogout.persistentState(for: source).hasLoginState)
        let header = await SourceCookieStore(storageURL: location).cookieHeader(for: URL(string: source.bookSourceUrl)!)
        XCTAssertNil(header)
    }

    func testCookieReadDoesNotFallBackToAnotherHostsSession() async throws {
        let cookies = SourceCookieStore(storageURL: nil)
        let url = URL(string: "https://login.fixture.invalid/")!
        await cookies.storeSetCookieHeaders(["Set-Cookie": "session=fixture; Path=/"], for: url)
        let context = RuleExecutionContext(initialValues: ["cookieHeader": "session=fixture"])
        context.scriptCookies = SourceScriptCookieBridge(store: cookies)
        let result = await BlockingRuleExecutor.run {
            context.jsRuntime(ajaxHandler: { _ in "" }).evaluate("cookie.getCookie('https://unrelated.invalid/')")
        }
        XCTAssertEqual(try result.get(), "")
    }

    func testCancellationBeforeDelayedBrowserCallStopsAllLoginEntryPoints() async throws {
        for entry in ["action", "fields", "login"] {
            let waiting = expectation(description: "\(entry) reached its pre-browser request")
            let network = SuspendedLoginRequest(waiting: waiting)
            let browser = LoginBrowserCalls()
            let script = """
            java.ajax(source.bookSourceUrl + '/prepare');
            var response = java.startBrowserAwait(source.bookSourceUrl + '/login', '登录', false);
            source.put('completedURL', response.url());
            """
            let source = BookSource(bookSourceName: "Cancelled \(entry)", bookSourceUrl: "https://cancel.fixture.invalid",
                loginUrl: entry == "login" ? script : "function signIn() { \(script) }",
                loginUi: entry == "fields" ? "@js:signIn(); JSON.stringify([])" : #"[{"name":"account","type":"text"}]"#)
            let engine = LegadoSourceEngine(network: network, cookieStore: SourceCookieStore(storageURL: nil),
                browserLoginProvider: { url, _ in
                    browser.open()
                    return SourceResponse(url: url, statusCode: 200, headers: [:], body: "", data: Data())
                })
            let operation = Task { () -> Bool in
                switch entry {
                case "action":
                    if case .failure = await engine.performLoginInteraction(source: source, action: "signIn()", credentials: [:]) { return true }
                case "fields":
                    if case .failure = await engine.loginFields(source: source) { return true }
                default:
                    if case .failure = await engine.login(source: source, credentials: ["account": "fixture"]) { return true }
                }
                return false
            }
            await fulfillment(of: [waiting], timeout: 3)
            operation.cancel()
            await network.release()
            let wasCancelled = await operation.value
            XCTAssertTrue(wasCancelled, "\(entry) returned success after cancellation")
            XCTAssertEqual(browser.count, 0, "\(entry) opened a browser after its UI was closed")
            XCTAssertTrue(engine.persistentState(for: source).get("source.variable.completedURL").isEmpty)
        }
    }
}

private final class LoginSessionSecrets: SecretStoring {
    private var values: [String: String] = [:]
    func set(_ value: String, for key: String) throws { values[key] = value }
    func value(for key: String) -> String? { values[key] }
    func removeValue(for key: String) throws { values.removeValue(forKey: key) }
}

private actor SessionRequestFixture: SourceNetworkClient {
    let cookies: SourceCookieStore
    private(set) var lastAuthorization: String?
    init(cookies: SourceCookieStore) { self.cookies = cookies }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        lastAuthorization = request.headers["X-Reader-Token"]
        let cookie = await cookies.cookieHeader(for: request.url)
        guard lastAuthorization == "fixture-header", cookie == "reader.token=fixture-session" else {
            return .failure(.network("Fixture session was lost"))
        }
        let body = #"{"books":[{"name":"Authenticated fixture","url":"https://login.fixture.invalid/book"}]}"#
        return .success(SourceResponse(url: request.url, statusCode: 200,
            headers: ["Content-Type": "application/json"], body: body, data: Data(body.utf8)))
    }
}

private actor SuspendedLoginRequest: SourceNetworkClient {
    private let waiting: XCTestExpectation
    private var pending: CheckedContinuation<Void, Never>?
    private var isReleased = false
    init(waiting: XCTestExpectation) { self.waiting = waiting }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        if !isReleased {
            await withCheckedContinuation { continuation in
                pending = continuation
                waiting.fulfill()
            }
        }
        return .success(SourceResponse(url: request.url, statusCode: 200, headers: [:], body: "ready", data: Data("ready".utf8)))
    }

    func release() {
        isReleased = true
        let continuation = pending
        pending = nil
        continuation?.resume()
    }
}

private final class LoginBrowserCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var openings = 0
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return openings
    }
    func open() {
        lock.lock(); openings += 1; lock.unlock()
    }
}
