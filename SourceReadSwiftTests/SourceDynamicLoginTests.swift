import XCTest
@testable import SourceReadSwift

final class SourceDynamicLoginTests: XCTestCase {
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
