import XCTest
@testable import SourceReadSwift

final class SourceLoginFieldTests: XCTestCase {

    // MARK: - loginUi parsing (Legado RowUi)

    func testParsesLegadoLoginUiArray() {
        let raw = #"[{"name":"账号","type":"text"},{"name":"密码","type":"password"},{"name":"注册","type":"button","action":"https://example.com/reg"}]"#
        let fields = SourceLoginFieldParser.parse(raw)

        XCTAssertEqual(fields.count, 3)
        XCTAssertEqual(fields[0].name, "账号")
        XCTAssertEqual(fields[0].type, .text)
        XCTAssertEqual(fields[1].type, .password)
        XCTAssertEqual(fields[2].type, .button)
        XCTAssertEqual(fields[2].action, "https://example.com/reg")
    }

    func testMissingTypeDefaultsToText() {
        let fields = SourceLoginFieldParser.parse(#"[{"name":"手机号"}]"#)
        XCTAssertEqual(fields.count, 1)
        XCTAssertEqual(fields[0].type, .text)
    }

    func testAcceptsBareObjectAndRelaxedJSON() {
        XCTAssertEqual(SourceLoginFieldParser.parse(#"{"name":"令牌","type":"password"}"#).count, 1)
        let relaxed = SourceLoginFieldParser.parse("[{'name':'账号','type':'text'},{'name':'密码','type':'password'},]")
        XCTAssertEqual(relaxed.map(\.name), ["账号", "密码"])
    }

    func testRejectsEmptyAndMalformedValues() {
        XCTAssertTrue(SourceLoginFieldParser.parse(nil).isEmpty)
        XCTAssertTrue(SourceLoginFieldParser.parse("").isEmpty)
        XCTAssertTrue(SourceLoginFieldParser.parse("   ").isEmpty)
        XCTAssertTrue(SourceLoginFieldParser.parse("null").isEmpty)
        XCTAssertTrue(SourceLoginFieldParser.parse(#"[{"type":"text"}]"#).isEmpty)
    }

    func testKeepsUnknownTypeAsText() {
        let fields = SourceLoginFieldParser.parse(#"[{"name":"验证码","type":"number"}]"#)
        XCTAssertEqual(fields.first?.type, .text)
    }

    func testDecoratedPublisherLoginSelectsTheExactAuthoredAction() {
        for title in ["♥登录书源", "🔅登录账号"] {
            let fields = [
                SourceLoginField(name: "检测登录", type: .button, action: "checkStatus()"),
                SourceLoginField(name: title, type: .button, action: "login(true)"),
                SourceLoginField(name: "退出登录", type: .button, action: "logout()")
            ]
            XCTAssertEqual(SourceLoginFieldParser.primarySignInAction(in: fields), "login(true)")
        }
    }

    func testBookshanAccountLoginSelectsTheExactAuthoredAction() {
        for title in ["⭕账号登录", "⭕帐号登录"] {
            let fields = [
                SourceLoginField(name: "🔅用户中心", type: .button, action: "user()"),
                SourceLoginField(name: "❌退出登录", type: .button, action: "logout()"),
                SourceLoginField(name: title, type: .button, action: "login(true)")
            ]
            XCTAssertEqual(SourceLoginFieldParser.primarySignInAction(in: fields), "login(true)")
        }
    }

    func testPrimarySignInActionDoesNotRunChecksOrAccountMaintenance() {
        let fields = [
            SourceLoginField(name: "登录", type: .button, action: " "),
            SourceLoginField(name: "登录账号", type: .text, action: "notAnAction()"),
            SourceLoginField(name: "账号登录", type: .text, action: "login(true)"),
            SourceLoginField(name: "检测登录", type: .button, action: "checkStatus()"),
            SourceLoginField(name: "退出登录", type: .button, action: "logout()"),
            SourceLoginField(name: "🔅用户中心", type: .button, action: "user()"),
            SourceLoginField(name: "账户中心", type: .button, action: "user()"),
            SourceLoginField(name: "切换账号", type: .button, action: "login(true)"),
            SourceLoginField(name: "番茄登录", type: .button, action: "secondaryLogin()")
        ]
        XCTAssertNil(SourceLoginFieldParser.primarySignInAction(in: fields))
        XCTAssertEqual(SourceLoginFieldParser.primarySignInAction(in:
            fields + [SourceLoginField(name: "登录", type: .button, action: "signIn()")]), "signIn()")
    }

    // MARK: - loginUrl script extraction (Legado getLoginJs)

    func testStripsAtJSPrefix() {
        XCTAssertEqual(
            SourceLoginScript.script(from: #"@js:java.login("a")"#),
            #"java.login("a")"#
        )
    }

    func testStripsJSTag() {
        XCTAssertEqual(
            SourceLoginScript.script(from: "<js>cookie.put('k','v')</js>"),
            "cookie.put('k','v')"
        )
    }

    func testBareScriptIsReturnedAsIs() {
        XCTAssertEqual(SourceLoginScript.script(from: "java.login('x')"), "java.login('x')")
    }

    func testEmptyLoginUrlHasNoScript() {
        XCTAssertNil(SourceLoginScript.script(from: nil))
        XCTAssertNil(SourceLoginScript.script(from: ""))
        XCTAssertNil(SourceLoginScript.script(from: "  "))
    }

    func testPageURLIsNotTreatedAsScript() {
        XCTAssertTrue(SourceLoginScript.isPageURL("https://example.com/login"))
        XCTAssertTrue(SourceLoginScript.isPageURL("/user/login.php"))
        XCTAssertTrue(SourceLoginScript.isPageURL("//example.com/signin"))
        XCTAssertFalse(SourceLoginScript.isPageURL("@js:java.login('x')"))
        XCTAssertFalse(SourceLoginScript.isPageURL(nil))
    }

    func testLoginInfoKeysUseTheJavaScriptNamespace() {
        XCTAssertEqual(SourceLoginScript.loginInfoKey("账号"), "source.login.账号")
        XCTAssertEqual(SourceLoginScript.loginInfoPrefix, "source.login.")
    }

    // MARK: - SourceRequestBuilder round trip

    func testBookSourceDecodesLoginUiIntoRaw() throws {
        let json = #"{"bookSourceName":"登录源","bookSourceUrl":"https://example.com","loginUi":[{"name":"账号","type":"text"}],"loginUrl":"@js:java.login('x')"}"#
        let source = try JSONDecoder().decode(BookSource.self, from: Data(json.utf8))

        XCTAssertEqual(source.loginUi?.contains("账号"), true)
        XCTAssertEqual(SourceLoginFieldParser.parse(source.loginUi).first?.name, "账号")
        XCTAssertEqual(source.raw["loginUi"]?.contains("账号"), true)
    }
}
