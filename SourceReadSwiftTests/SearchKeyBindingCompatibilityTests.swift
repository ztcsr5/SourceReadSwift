import JavaScriptCore
import XCTest
@testable import SourceReadSwift

final class SearchKeyBindingCompatibilityTests: XCTestCase {
    private let selfInitializingKey = "let key = java.encodeURI(key); key;"

    func testSearchKeyInitializerUsesHostBindingAndWritesItBack() throws {
        let normalized = LegadoSearchKeyCompatibility.normalize(selfInitializingKey, hasHostKey: true)
        let runtime = JSCoreRuntime()
        XCTAssertEqual(try runtime.evaluate(normalized, variables: ["key": "fixture key"]).get(), "fixture%20key")
        XCTAssertEqual(runtime.context.objectForKeyedSubscript("key")?.toString(), "fixture%20key")
    }

    func testOnlyTheUniqueTopLevelSelfInitializingDeclarationChanges() {
        let script = "let prefix = 'fixture'; let key = java.encodeURI(key); const suffix = '/'; prefix + key + suffix;"
        XCTAssertEqual(LegadoSearchKeyCompatibility.normalize(script, hasHostKey: true),
                       "let prefix = 'fixture'; var key = java.encodeURI(key); const suffix = '/'; prefix + key + suffix;")
        XCTAssertEqual(LegadoSearchKeyCompatibility.normalize(selfInitializingKey, hasHostKey: false), selfInitializingKey)
    }

    func testLiteralAndCommentContentsDoNotBecomeBindingsOrSelfReferences() {
        let script = "// let key = key;\nlet label = '中文😀 let key = key'; /* const key = 0; */ let key = java.encodeURI(key); key;"
        XCTAssertEqual(LegadoSearchKeyCompatibility.normalize(script, hasHostKey: true),
                       script.replacingOccurrences(of: "let key = java.encodeURI", with: "var key = java.encodeURI"))
        for unchanged in ["let key = 'key'; key;", "let key = /key/.source; key;", "let key = object.key; key;"] {
            XCTAssertEqual(LegadoSearchKeyCompatibility.normalize(unchanged, hasHostKey: true), unchanged)
        }
    }

    func testASIDeclarationBoundariesAndURLLiteralsKeepTheActualRuleShapeEligible() throws {
        let script = """
        let origin = 'https://fixture.invalid'
        let label = 'synthetic'
        let identifier = '42'
        let key = java.encodeURI(key)
        let address = origin + '/search?q=' + key
        let body = 'identifier=' + identifier
        let headers = {
          'Content-Type': 'application/x-www-form-urlencoded'
        }
        let options = {
          method: 'POST',
          body: body,
          headers: headers
        }
        address
        """
        let normalized = LegadoSearchKeyCompatibility.normalize(script, hasHostKey: true)
        XCTAssertEqual(normalized, script.replacingOccurrences(of: "let key =", with: "var key ="))
        XCTAssertEqual(try JSCoreRuntime().evaluate(normalized, variables: ["key": "fixture key"]).get(),
                       "https://fixture.invalid/search?q=fixture%20key")
    }

    func testConstOrdinaryLetNestedBindingsAndAmbiguousSyntaxStayUntouched() {
        let scripts = [
            "const key = java.encodeURI(key); key;",
            "let key = 'local'; key;",
            "let encoded = java.encodeURI(key); encoded;",
            "{ let key = java.encodeURI(key); key; }",
            "function encode() { let key = java.encodeURI(key); return key; } encode();",
            "(() => { let key = java.encodeURI(key); return key; })();",
            "let key = (() => key)(); key;",
            "let key = {encode(key) { return key; }}.encode('local'); key;",
            "for (let key = java.encodeURI(key); false;) {}",
            "let key = `prefix ${key}`; key;",
            "let key = key / 2; key;",
            "'use strict'; let key = java.encodeURI(key); key;",
            "let key = java.encodeURI(key)\nkey;"
        ]
        for script in scripts {
            XCTAssertEqual(LegadoSearchKeyCompatibility.normalize(script, hasHostKey: true), script)
        }
    }

    func testRedeclarationsRemainSyntaxErrors() {
        let scripts = [
            "let key = java.encodeURI(key); let key = 'again';",
            "var key = 'first'; let key = java.encodeURI(key);",
            "let key = java.encodeURI(key); const key = 'again';",
            "let key = java.encodeURI(key); let [key] = ['again'];",
            "let key = java.encodeURI(key); var other = 1, key = 'again';",
            "let key = java.encodeURI(key); { var key = 'again'; }"
        ]
        for script in scripts {
            let normalized = LegadoSearchKeyCompatibility.normalize(script, hasHostKey: true)
            XCTAssertEqual(normalized, script)
            XCTAssertThrowsError(try JSCoreRuntime().evaluate(normalized, variables: ["key": "fixture key"]).get())
        }
    }

    func testExistingLibraryLexicalBindingIsNotOverwritten() throws {
        let runtime = JSCoreRuntime()
        try runtime.preloadJavaScriptLibrary("let key = 'library';").get()
        let normalized = LegadoSearchKeyCompatibility.normalize(selfInitializingKey, hasHostKey: true)
        XCTAssertThrowsError(try runtime.evaluate(normalized, variables: ["key": "fixture key"]).get())
        XCTAssertEqual(try runtime.evaluate("key;").get(), "library")
    }

    func testSearchResolverEnablesCompatibilityButExploreAndGeneralRulesDoNot() throws {
        let script = "let key = java.encodeURI(key); 'https://fixture.invalid/search?q=' + key;"
        let source = BookSource(bookSourceName: "Synthetic key binding", bookSourceUrl: "https://fixture.invalid",
                                searchUrl: "@js:" + script)
        XCTAssertEqual(try SearchURLResolver().resolve(source: source, keyword: "fixture key", page: 1).get(),
                       "https://fixture.invalid/search?q=fixture%20key")
        XCTAssertThrowsError(try SearchURLResolver().resolveExplore("@js:" + script, source: source, page: 1,
                            context: RuleExecutionContext(source: source)).get())
        XCTAssertThrowsError(try JSCoreRuntime().evaluate(selfInitializingKey, variables: ["key": "fixture key"]).get())
        XCTAssertEqual(LegadoJavaScriptCompatibility.normalizeRuleScript(selfInitializingKey), selfInitializingKey)
    }
}
