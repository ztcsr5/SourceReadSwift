import XCTest
@testable import SourceReadSwift

final class SourceLoginRegistrationTests: XCTestCase {
    func testRegistrationKeepsAuthoredHashRouteAndWaitsForBrowserResult() async throws {
        let source = BookSource(bookSourceName: "Registration fixture", bookSourceUrl: "https://register.fixture.invalid",
            loginUrl: """
            function register() {
                var page = java.startBrowserAwait(source.bookSourceUrl + '/spa/#/register', '注册');
                source.put('registrationResult', page.url());
            }
            """, loginUi: #"[{"name":"注册","type":"button","action":"register()"}]"#)
        let engine = LegadoSourceEngine(cookieStore: SourceCookieStore(storageURL: nil), browserLoginProvider: { url, title in
            XCTAssertEqual(url.path, "/spa/")
            XCTAssertEqual(url.fragment, "/register")
            XCTAssertEqual(title, "注册")
            let final = URL(string: "https://register.fixture.invalid/spa/#/login")!
            let body = "<p>已注册</p>"
            return SourceResponse(url: final, statusCode: 200, headers: [:], body: body, data: Data(body.utf8))
        })
        let result = try await engine.performLoginInteraction(source: source, action: "register()", credentials: [:]).get()
        XCTAssertNil(result.destination)
        XCTAssertEqual(engine.persistentState(for: source).get("source.variable.registrationResult"),
                       "https://register.fixture.invalid/spa/#/login")
    }

    func testDynamicAPIKeyConfigurationRunsTheAuthoredSaveFunction() async throws {
        let source = BookSource(bookSourceName: "API Key configuration", bookSourceUrl: "https://config.fixture.invalid",
            loginUrl: "function login() { source.put('apikey', String(source.getLoginInfoMap().get('apikey'))); }",
            loginUi: #"@js:JSON.stringify([{name:'apikey',type:'password'}])"#)
        let engine = LegadoSourceEngine(cookieStore: SourceCookieStore(storageURL: nil))
        _ = try await engine.performLoginInteraction(source: source,
            action: "if (typeof login === 'function') { login(); }",
            credentials: ["apikey": "fixture-key"]).get()
        XCTAssertEqual(engine.persistentState(for: source).get("source.variable.apikey"), "fixture-key")
        let verification = try await engine.verifyLogin(source: source).get()
        XCTAssertEqual(verification.status, .notConfigured)
    }

    func testRegistrationURLResolverDoesNotDropHashOrQuery() {
        let target = SourceLoginURLResolver.resolve(loginUrl: "/spa/?client=reader#/register",
            bookSourceUrl: "https://register.fixture.invalid")
        XCTAssertEqual(target?.url.absoluteString, "https://register.fixture.invalid/spa/?client=reader#/register")
        XCTAssertEqual(SourceLoginBrowserAction.loginWebURL("https://register.fixture.invalid/spa/#/register")?.fragment,
                       "/register")
    }

    func testStaticInlineLoginWithoutAButtonAuthenticatesExactlyOnce() async throws {
        let source = BookSource(bookSourceName: "Static login fixture", bookSourceUrl: "https://login.fixture.invalid",
            loginUrl: """
            function login() {
                source.put('attempts', String(Number(source.get('attempts') || '0') + 1));
                source.put('submitted', String(source.getLoginInfoMap().get('账号')));
                java.toast('表单已提交');
            }
            login();
            """,
            loginUi: #"[{"name":"账号","type":"text"},{"name":"密码","type":"password"}]"#)
        XCTAssertNil(SourceLoginFieldParser.primarySignInAction(in: SourceLoginFieldParser.parse(source.loginUi)))
        let engine = LegadoSourceEngine(cookieStore: SourceCookieStore(storageURL: nil))
        let interaction = try await engine.performLoginInteraction(source: source,
            action: "void 0", credentials: ["账号": "fixture-reader"]).get()
        XCTAssertEqual(engine.persistentState(for: source).get("source.variable.attempts"), "1")
        XCTAssertEqual(engine.persistentState(for: source).get("source.variable.submitted"), "fixture-reader")
        XCTAssertEqual(interaction.messages, ["表单已提交"])
    }
}
