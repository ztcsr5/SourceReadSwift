import XCTest
@testable import SourceReadSwift

final class SourceDynamicLoginTests: XCTestCase {
    func testFormLoginAndCheckUseTheInjectedTransportAndCurrentSession() async throws {
        let network = LoginFixtureNetwork()
        let engine = LegadoSourceEngine(network: network, cookieStore: SourceCookieStore(storageURL: nil))
        let source = BookSource(bookSourceName: "Form login", bookSourceUrl: "https://fixture.test",
            searchUrl: "https://fixture.test/search?q={{key}}",
            ruleSearch: SourceRule(fields: ["bookList": "$.data", "name": "name", "bookUrl": "url"]),
            loginUrl: """
            var account = source.getLoginInfoMap().get('账号');
            var response = JSON.parse(java.ajax('https://fixture.test/login?account=' + account));
            source.putLoginHeader(JSON.stringify({'Authorization': 'Bearer ' + response.token}));
            """, loginCheckJs: "java.ajax('https://fixture.test/verify')",
            loginUi: #"[{"name":"账号","type":"text"}]"#)
        let verification = try await engine.login(source: source, credentials: ["账号": "fixture-user"]).get()
        XCTAssertEqual(verification.status, .passed)
        _ = try await engine.searchBooks(source: source, keyword: "fixture", page: 1).get()
        let requests = await network.requests
        XCTAssertEqual(requests.map { $0.url.path }, ["/login", "/verify", "/search"])
        for request in requests.dropFirst() {
            XCTAssertEqual(request.headers["Authorization"], "Bearer fixture-token")
            XCTAssertTrue((request.headers["Cookie"] ?? "").contains("session=fixture-session"))
        }
    }

    func testDynamicLoginUIUsesLibraryAndLoginDefinitions() async throws {
        let source = source(loginURL: """
        // configuration, not a protocol-relative login URL
        function nextMenu() { source.put('menu', 'settings'); }
        """, loginUI: """
        @js:
        let menu = source.get('menu') || 'home';
        JSON.stringify([{name: libraryTitle() + ':' + menu, type:'button', action:'nextMenu()'}]);
        """, library: "var host = source.bookSourceUrl; function libraryTitle() { return host; }")
        let engine = LegadoSourceEngine(network: LoginFixtureNetwork())
        let initial = try await engine.loginFields(source: source).get()
        XCTAssertEqual(initial.first?.name, "https://fixture.test:home")
        XCTAssertEqual(initial.first?.action, "nextMenu()")
        let refreshed = try await engine.performLoginAction(source: source, action: "nextMenu()", credentials: [:]).get()
        XCTAssertEqual(refreshed.first?.name, "https://fixture.test:settings")
        let reopened = try await engine.loginFields(source: source).get()
        XCTAssertEqual(reopened.first?.name, "https://fixture.test:settings")
    }

    func testLoginActionCarriesCredentialsHeadersAndCookiesIntoSearch() async throws {
        let network = LoginFixtureNetwork()
        let engine = LegadoSourceEngine(network: network)
        let source = source(loginURL: """
        function login() {
            var account = source.getLoginInfoMap().get('账号');
            var response = JSON.parse(java.ajax('https://fixture.test/login?account=' + account));
            source.putLoginHeader(JSON.stringify({'Authorization': 'Bearer ' + response.token}));
        }
        """, loginUI: #"[{"name":"账号","type":"text"},{"name":"登录","type":"button","action":"login()"}]"#)
        _ = try await engine.performLoginAction(source: source, action: "login()", credentials: ["账号": "fixture-user"]).get()
        let books = try await engine.searchBooks(source: source, keyword: "fixture", page: 1).get()
        XCTAssertEqual(books.first?.name, "Fixture book")
        let requests = await network.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests[0].url.absoluteString.contains("account=fixture-user"))
        XCTAssertEqual(requests[1].headers["Authorization"], "Bearer fixture-token")
        XCTAssertTrue((requests[1].headers["Cookie"] ?? "").contains("session=fixture-session"))
    }

    func testBookshanAccountLoginReadsResultMapAndCarriesRawAuthorizationIntoSearch() async throws {
        BookshanLoginURLProtocol.registry.reset()
        defer { BookshanLoginURLProtocol.registry.reset() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BookshanLoginURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let cookies = SourceCookieStore(storageURL: nil)
        let network = URLSessionSourceNetworkClient(session: session, cookieStore: cookies)
        let engine = LegadoSourceEngine(network: network, cookieStore: cookies)
        engine.allowWebViewFallback = false
        let source = BookSource(bookSourceName: "Bookshan login fixture",
            bookSourceUrl: "https://bookshan-login.fixture.invalid",
            searchUrl: "/api/search?keyword={{key}}",
            ruleSearch: SourceRule(fields: ["bookList": "$.data", "name": "name", "bookUrl": "url"]),
            header: "@js: JSON.stringify({'X-Reader-Auth': source.getLoginHeader()});",
            loginUrl: """
            function login(flag) {
                if (flag !== true) throw new Error('Expected the authored login argument');
                var email = result.get('邮箱');
                var password = result.get('密码');
                if (!email || !password) return;
                var options = {method: 'POST',
                    body: JSON.stringify({email: email, password: password})};
                var response = JSON.parse(java.ajax(source.bookSourceUrl + '/api/login,' + JSON.stringify(options)));
                if (response.code !== 0) throw new Error('Fixture login rejected');
                source.putLoginHeader(response.data.token);
                result.邮箱 = 'temporary@example.test';
                result['temporary-login-field'] = 'temporary';
            }
            """,
            loginUi: #"[{"name":"邮箱","type":"text"},{"name":"密码","type":"password"},{"name":"⭕账号登录","type":"button","action":"login(true)"}]"#)
        let action = try XCTUnwrap(SourceLoginFieldParser.primarySignInAction(in: SourceLoginFieldParser.parse(source.loginUi)))
        _ = try await engine.performLoginInteraction(source: source, action: action,
            credentials: ["邮箱": "fixture@example.test", "密码": "fixture-password"]).get()
        let state = engine.persistentState(for: source)
        XCTAssertEqual(state.get("source.loginHeader"), "fixture-raw-token")
        XCTAssertEqual(state.get(SourceLoginScript.loginInfoKey("邮箱")), "fixture@example.test")
        XCTAssertNil(state.storedString(for: SourceLoginScript.loginInfoKey("temporary-login-field")))
        let books = try await engine.searchBooks(source: source, keyword: "fixture", page: 1).get()
        XCTAssertEqual(books.first?.name, "Authenticated bookshan fixture")
        let requests = BookshanLoginURLProtocol.registry.requests
        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/login", "/api/search"])
        let login = try XCTUnwrap(requests.first)
        XCTAssertEqual(login.httpMethod, "POST")
        XCTAssertEqual(login.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
        let credentials = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(login.httpBody))
        XCTAssertEqual(credentials, ["email": "fixture@example.test", "password": "fixture-password"])
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "X-Reader-Auth"), "fixture-raw-token")
    }

    func testDynamicLoginUIResultMapIsAnIsolatedSnapshotAndKeepsTheFinalExpression() async throws {
        let engine = LegadoSourceEngine(network: LoginFixtureNetwork(), cookieStore: SourceCookieStore(storageURL: nil))
        let source = source(loginURL: nil, loginUI: """
        @js:
        if (result.get('missing') !== null) throw new Error('Missing form fields must return null');
        if (result.邮箱 !== result.get('邮箱')) throw new Error('Map reads must preserve field properties');
        if (Object.keys(result).join(',') !== '邮箱') throw new Error('Map methods must not be enumerable');
        if (JSON.stringify(result) !== JSON.stringify({'邮箱': 'fixture@example.test'}))
            throw new Error('Map methods must not appear in JSON');
        if (String(result) !== JSON.stringify(result)) throw new Error('Keep existing form string coercion');
        if (typeof ({}).get !== 'undefined') throw new Error('Ordinary objects must not gain Map methods');
        result['temporary-login-field'] = 'temporary';
        JSON.stringify([{name: result.get('邮箱'), type: 'text'}]);
        """)
        let fields = try await engine.performLoginAction(source: source,
            action: "result.邮箱 = 'temporary@example.test';",
            credentials: ["邮箱": "fixture@example.test"]).get()
        XCTAssertEqual(fields.first?.name, "fixture@example.test")
        XCTAssertNil(engine.persistentState(for: source).storedString(for: SourceLoginScript.loginInfoKey("temporary-login-field")))
    }

    func testInlineLoginReceivesTheSameIsolatedResultMap() async throws {
        let engine = LegadoSourceEngine(network: LoginFixtureNetwork(), cookieStore: SourceCookieStore(storageURL: nil))
        let source = source(loginURL: """
        source.put('submitted-email', result.get('邮箱'));
        result.邮箱 = 'temporary@example.test';
        """, loginUI: #"[{"name":"邮箱","type":"text"}]"#)
        _ = try await engine.login(source: source, credentials: ["邮箱": "fixture@example.test"]).get()
        let state = engine.persistentState(for: source)
        XCTAssertEqual(state.get("source.variable.submitted-email"), "fixture@example.test")
        XCTAssertEqual(state.get(SourceLoginScript.loginInfoKey("邮箱")), "fixture@example.test")
    }

    func testStrictLoginScriptStillRejectsUndeclaredAssignments() async throws {
        let engine = LegadoSourceEngine(network: LoginFixtureNetwork(), cookieStore: SourceCookieStore(storageURL: nil))
        let source = source(loginURL: """
        'use strict';
        if (result.get('邮箱') !== 'fixture@example.test') throw new Error('Missing strict form input');
        unboundLoginFormField = 1;
        """, loginUI: #"[{"name":"邮箱","type":"text"}]"#)
        switch await engine.login(source: source, credentials: ["邮箱": "fixture@example.test"]) {
        case .success: XCTFail("Keep the authored strict-mode error")
        case .failure(let error):
            XCTAssertTrue(error.displayMessage.contains("ReferenceError"), error.displayMessage)
            XCTAssertTrue(error.displayMessage.contains("unboundLoginFormField"), error.displayMessage)
        }
    }

    func testPublisherSignInKeepsAuthAndAuthoredVersionInNestedChapterPOST() async throws {
        let network = LoginFixtureNetwork()
        let engine = LegadoSourceEngine(network: network)
        let form = #"[{"name":"账号","type":"text"},{"name":"🔅登录账号","type":"button","action":"login(true)"}]"#
        let source = BookSource(bookSourceName: "Authenticated chapter fixture", bookSourceUrl: "https://fixture.test",
            ruleContent: SourceRule(fields: ["content": "$.body"]),
            loginUrl: """
            function login(confirm) {
                if (!confirm) throw new Error('expected authored argument');
                var account = source.getLoginInfoMap().get('账号');
                var response = JSON.parse(java.ajax('https://fixture.test/login?account=' + account));
                source.putLoginHeader(JSON.stringify({'Authorization': 'Bearer ' + response.token}));
            }
            """, loginUi: form)
        let action = try XCTUnwrap(SourceLoginFieldParser.primarySignInAction(in: SourceLoginFieldParser.parse(form)))
        _ = try await engine.performLoginInteraction(source: source, action: action, credentials: ["账号": "fixture-user"]).get()
        let bodyHook = """
        var options = {method: 'POST', headers: {'Content-Type': 'application/json'},
                       body: JSON.stringify({version: '1.2.3', chapter: 1})};
        java.ajax('https://fixture.test/chapter-api,' + JSON.stringify(options));
        """
        let directives = try JSONSerialization.data(withJSONObject: ["bodyJs": bodyHook])
        let chapter = BookChapter(title: "Fixture", url: "https://fixture.test/chapter," + String(decoding: directives, as: UTF8.self),
            bookUrl: "https://fixture.test/book/1", index: 0)
        let loaded = try await engine.getContent(source: source, chapter: chapter, maxPages: 1).get()
        XCTAssertTrue(loaded.paragraphs.joined().contains("这是授权后的测试正文"))
        let requests = await network.requests
        XCTAssertEqual(requests.map { $0.url.path }, ["/login", "/chapter", "/chapter-api"])
        let nested = try XCTUnwrap(requests.last)
        XCTAssertEqual(nested.method, .post)
        XCTAssertEqual(nested.headers["Authorization"], "Bearer fixture-token")
        XCTAssertTrue((nested.headers["Cookie"] ?? "").contains("session=fixture-session"))
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(nested.body)) as? [String: Any]
        XCTAssertEqual(json?["version"] as? String, "1.2.3")
    }

    func testUpdateButtonExposesOnlyExplicitHTTPSLinksWithoutLoadingThePage() async throws {
        let network = LoginFixtureNetwork()
        let engine = LegadoSourceEngine(network: network)
        let source = source(loginURL: #"""
        function update() {
            let page = '<a href="yuedu://booksource/importonline?src=https%3A%2F%2Fpublisher.invalid%2Fsource.json">更新书源</a>'
                + '<a href="javascript:open(\'https://wrong.invalid\')">unsafe</a>'
                + '<a href="http://publisher.invalid/untrusted.json">cleartext</a>'
                + '<script>fetch("https://ignored.invalid/source.json");</script>';
            java.startBrowser('data:text/html;base64,' + java.base64Encode(page), 'version');
        }
        """#, loginUI: #"[{"name":"更新书源","type":"button","action":"update()"}]"#)
        let result = try await engine.performLoginInteraction(source: source, action: "update()", credentials: [:]).get()
        guard case .publisher(let links)? = result.destination else { return XCTFail("Expected publisher links") }
        XCTAssertEqual(links.map(\.title), ["更新书源"])
        XCTAssertEqual(links.map { $0.url.absoluteString }, ["https://publisher.invalid/source.json"])
        XCTAssertFalse(try XCTUnwrap(links.first).isPageReference)
        let requests = await network.requests
        XCTAssertTrue(requests.isEmpty, "Inspecting a publisher page must not run its scripts or import a link")
    }

    func testAwaitedBrowserIsOnlyAnExplicitHandoffNotAFabricatedLogin() async throws {
        let network = LoginFixtureNetwork()
        let engine = LegadoSourceEngine(network: network)
        let source = source(loginURL: #"""
        function loginPage() {
            java.startBrowserAwait('https://publisher.invalid/login', 'login');
            source.put('browserLoginCompleted', 'true');
        }
        """#, loginUI: #"[{"name":"网页登录","type":"button","action":"loginPage()"}]"#)
        let result = try await engine.performLoginInteraction(source: source, action: "loginPage()", credentials: [:]).get()
        XCTAssertEqual(result.destination, .web(URL(string: "https://publisher.invalid/login")!, waitsForAndroidResult: true))
        XCTAssertTrue(engine.persistentState(for: source).get("source.variable.browserLoginCompleted").isEmpty)
        let requests = await network.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testDynamicLoginUIErrorIsNotAnEmptyFormSuccess() async {
        let source = source(loginURL: nil, loginUI: "@js:throw new Error('bad login menu')")
        let engine = LegadoSourceEngine(network: LoginFixtureNetwork())
        switch await engine.loginFields(source: source) {
        case .success: XCTFail("Do not hide a failed JS menu as an empty form")
        case .failure(let error): XCTAssertTrue(error.displayMessage.contains("bad login menu"))
        }
    }

    func testAJAXCookieIsVisibleInTheSameRuleAndSurvivesTheNextRule() throws {
        let state = RulePersistentState()
        let context = RuleExecutionContext(persistentState: state)
        context.responseHandler = { _ in
            SourceResponse(url: URL(string: "https://fixture.test/login")!, statusCode: 200,
                           headers: ["Set-Cookie": "session=fresh; Path=/"], body: "ok", data: Data())
        }
        let runtime = context.jsRuntime(ajaxHandler: { _ in "" })
        XCTAssertEqual(try runtime.evaluate("java.ajax('https://fixture.test/login'); cookieHeader").get(), "session=fresh")
        XCTAssertEqual(state.get("cookieHeader"), "session=fresh")
        XCTAssertEqual(try runtime.evaluate("cookieHeader").get(), "session=fresh")
        _ = try runtime.evaluate("cookieHeader = ''").get()
        XCTAssertEqual(state.get("cookieHeader"), "", "An explicit JS logout must still clear its cookie")
    }

    func testNameOnlySourceCanUseItsLibraryOriginForActions() async throws {
        let source = BookSource(bookSourceName: "Named source", bookSourceUrl: "书源标签",
                                loginUrl: "function choose() { source.put('chosen', '1'); }",
                                loginUi: #"[{"name":"选择","type":"button","action":"choose()"}]"#,
                                raw: ["jsLib": "var api = 'https://fixture.test';"])
        let engine = LegadoSourceEngine(network: LoginFixtureNetwork())
        _ = try await engine.performLoginAction(source: source, action: "choose()", credentials: [:]).get()
        XCTAssertEqual(engine.persistentState(for: source).get("source.variable.chosen"), "1")
        XCTAssertEqual(SourceLoginURLResolver.resolve(source: source)?.url.host, "fixture.test")
    }

    func testToggleChoicesAndDefaultsArePreserved() {
        let fields = SourceLoginFieldParser.parse(#"[{"title":"阅读模式","type":"toggle","chars":["小说","听书"],"default":"听书"}]"#)
        XCTAssertEqual(fields.first?.name, "阅读模式")
        XCTAssertEqual(fields.first?.type, .toggle)
        XCTAssertEqual(fields.first?.choices, ["小说", "听书"])
        XCTAssertEqual(fields.first?.defaultValue, "听书")
    }

    func testJSCommentsCannotBecomeLoginPages() {
        let script = "// ==== config ====\nvar host = source.bookSourceUrl;"
        XCTAssertFalse(SourceLoginScript.isPageURL(script))
        XCTAssertFalse(SourceLoginScript.isPageURL("/* comment */ function login() {}"))
        XCTAssertTrue(SourceLoginScript.isPageURL("//fixture.test/login"))
        XCTAssertEqual(SourceLoginURLResolver.resolve(loginUrl: script, bookSourceUrl: "https://fixture.test")?.usedBookSourceFallback, true)
        XCTAssertEqual(SourceLoginURLResolver.resolve(loginUrl: "function login() {}", bookSourceUrl: "https://fixture.test")?.url.absoluteString, "https://fixture.test")
    }

    private func source(loginURL: String?, loginUI: String, library: String = "") -> BookSource {
        BookSource(bookSourceName: "Login fixture", bookSourceUrl: "https://fixture.test",
                   searchUrl: "https://fixture.test/search?q={{key}}",
                   ruleSearch: SourceRule(fields: ["bookList": "$.data", "name": "name", "bookUrl": "url"]),
                   loginUrl: loginURL, loginUi: loginUI, raw: ["jsLib": library])
    }
}

private actor LoginFixtureNetwork: SourceNetworkClient {
    private(set) var requests: [SourceRequest] = []

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        requests.append(request)
        let login = request.url.path == "/login"
        var headers = ["Content-Type": "application/json"]
        if login { headers["Set-Cookie"] = "session=fixture-session; Path=/" }
        if request.url.path == "/verify" {
            let authorized = request.headers["Authorization"] == "Bearer fixture-token"
                && (request.headers["Cookie"] ?? "").contains("session=fixture-session")
            let body = authorized ? "true" : "false"
            return .success(SourceResponse(url: request.url, statusCode: 200,
                headers: headers, body: body, data: Data(body.utf8)))
        }
        if request.url.path == "/chapter-api" {
            let authorized = request.headers["Authorization"] == "Bearer fixture-token"
                && (request.headers["Cookie"] ?? "").contains("session=fixture-session")
            let body = authorized ? #"{"body":"这是授权后的测试正文，必须由章节接口返回并正常呈现。"}"# : #"{"error":"未授权"}"#
            return .success(SourceResponse(url: request.url, statusCode: authorized ? 200 : 401,
                headers: headers, body: body, data: Data(body.utf8)))
        }
        return .success(SourceResponse(url: request.url, statusCode: 200, headers: headers,
                                       body: login ? #"{"token":"fixture-token"}"# : #"{"data":[{"name":"Fixture book","url":"https://fixture.test/book/1"}]}"#, data: Data()))
    }
}

private final class BookshanLoginURLProtocol: URLProtocol {
    final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [URLRequest] = []

        var requests: [URLRequest] {
            lock.lock(); defer { lock.unlock() }
            return recorded
        }

        func record(_ request: URLRequest) {
            lock.lock(); defer { lock.unlock() }
            recorded.append(request)
        }

        func reset() {
            lock.lock(); defer { lock.unlock() }
            recorded = []
        }
    }

    static let registry = Registry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            var captured = request
            captured.httpBody = try readBody(request)
            Self.registry.record(captured)
            let status: Int
            let body: String
            switch captured.url?.path {
            case "/api/login":
                let credentials = captured.httpBody.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
                let accepted = captured.httpMethod == "POST"
                    && captured.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8"
                    && credentials == ["email": "fixture@example.test", "password": "fixture-password"]
                status = accepted ? 200 : 400
                body = accepted ? #"{"code":0,"data":{"token":"fixture-raw-token"}}"# : #"{"code":400}"#
            case "/api/search":
                let accepted = captured.value(forHTTPHeaderField: "X-Reader-Auth") == "fixture-raw-token"
                status = accepted ? 200 : 401
                body = accepted ? #"{"data":[{"name":"Authenticated bookshan fixture","url":"/book/1"}]}"# : #"{"code":40102}"#
            default:
                throw URLError(.badURL)
            }
            guard let url = captured.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                      headerFields: ["Content-Type": "application/json"]) else { throw URLError(.badServerResponse) }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func readBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { return body }
            body.append(contentsOf: buffer.prefix(count))
        }
    }
}
