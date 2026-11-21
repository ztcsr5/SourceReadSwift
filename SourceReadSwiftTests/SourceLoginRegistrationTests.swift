import XCTest
@testable import SourceReadSwift

final class SourceLoginRegistrationTests: XCTestCase {
    func testRegistrationKeepsAuthoredHashRouteAndWaitsForBrowserResult() async throws {
        let cookies = SourceCookieStore(storageURL: nil)
        let network = RegistrationFixtureNetwork()
        let source = BookSource(bookSourceName: "Registration fixture", bookSourceUrl: "https://register.fixture.invalid",
            loginUrl: """
            function register() {
                var page = java.startBrowserAwait(source.bookSourceUrl + '/spa/#/register', '注册');
                source.put('registrationResult', page.url());
                source.put('registrationOriginal', page.originalUrl());
                source.put('registrationBody', page.body());
                source.put('registrationStatus', page.code());
            }
            """, loginUi: #"[{"name":"注册","type":"button","action":"register()"}]"#)
        let engine = LegadoSourceEngine(network: network, cookieStore: cookies, browserLoginProvider: { url, title in
            XCTAssertEqual(url.absoluteString, "https://register.fixture.invalid/spa/#/register")
            XCTAssertEqual(title, "注册")
            _ = SourceScriptCookieBridge(store: cookies).perform(.write(url, "registration=complete; Path=/"))
            let final = URL(string: "https://register.fixture.invalid/spa/#/registered")!
            let body = "<p>已注册</p>"
            return SourceResponse(url: final, statusCode: 200, headers: [:], body: body, data: Data(body.utf8))
        })
        let result = try await engine.performLoginInteraction(source: source, action: "register()", credentials: [:]).get()
        XCTAssertNil(result.destination)
        let state = engine.persistentState(for: source)
        XCTAssertEqual(state.get("source.variable.registrationResult"), "https://register.fixture.invalid/spa/#/login")
        XCTAssertEqual(state.get("source.variable.registrationOriginal"), "https://register.fixture.invalid/spa/#/register")
        XCTAssertEqual(state.get("source.variable.registrationBody"), "<p>注册完成，请登录</p>")
        XCTAssertEqual(state.get("source.variable.registrationStatus"), "200")
        let requests = await network.requests
        XCTAssertEqual(requests.map { $0.url.absoluteString }, ["https://register.fixture.invalid/spa/#/register"])
        XCTAssertEqual(requests.first?.headers["Cookie"], "registration=complete")
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

private actor RegistrationFixtureNetwork: SourceNetworkClient {
    private(set) var requests: [SourceRequest] = []

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        requests.append(request)
        // Two-argument startBrowserAwait refetches the original address after the browser completes.
        let body = "<p>注册完成，请登录</p>"
        return .success(SourceResponse(url: URL(string: "https://register.fixture.invalid/spa/#/login")!,
            statusCode: 200, headers: [:], body: body, data: Data(body.utf8)))
    }
}
