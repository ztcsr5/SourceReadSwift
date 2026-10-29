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

    func testDynamicLoginUIErrorIsNotAnEmptyFormSuccess() async {
        let source = source(loginURL: nil, loginUI: "@js:throw new Error('bad login menu')")
        let engine = LegadoSourceEngine(network: LoginFixtureNetwork())
        switch await engine.loginFields(source: source) {
        case .success: XCTFail("Do not hide a failed JS menu as an empty form")
        case .failure(let error): XCTAssertTrue(error.displayMessage.contains("bad login menu"))
        }
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
        return .success(SourceResponse(url: request.url, statusCode: 200, headers: headers,
                                       body: login ? #"{"token":"fixture-token"}"# : #"{"data":[{"name":"Fixture book","url":"https://fixture.test/book/1"}]}"#, data: nil))
    }
}
