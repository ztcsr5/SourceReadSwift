import Foundation
import XCTest
@testable import SourceReadSwift

final class SourceScriptHeaderResolverTests: XCTestCase {
    func testStaticHeadersDoNotExecuteLibrary() throws {
        let source = makeSource(header: #"{"X-Static":"value"}"#, library: "throw new Error('must not run')")
        XCTAssertNil(try SourceScriptHeaderResolver.evaluate(source: source, context: RuleExecutionContext(source: source)).get())
    }

    func testLibraryCacheAndLoginValuesShareTheCurrentContext() throws {
        let source = makeSource(header: "@js: JSON.stringify(buildHeaders.call(this));", library: """
        var libraryBase = baseUrl;
        function buildHeaders() {
          return {'X-Base':libraryBase, 'X-Device':cache.get('device'),
                  'X-Account':source.getLoginInfoMap().get('account')};
        }
        """)
        let context = RuleExecutionContext(source: source)
        context.scriptCacheStore = SourceScriptCacheStore(isPersistent: false)
        let runtime = context.jsRuntime(ajaxHandler: { _ in "" })
        _ = try runtime.evaluate("cache.put('device','synthetic-device'); source.setLoginInfo('account','synthetic-account');",
            variables: ["source": source, "baseUrl": source.cleanSourceURL]).get()
        let headers = try XCTUnwrap(SourceScriptHeaderResolver.evaluate(source: source, context: context).get())
        XCTAssertEqual(headers["X-Base"], source.cleanSourceURL)
        XCTAssertEqual(headers["X-Device"], "synthetic-device")
        XCTAssertEqual(headers["X-Account"], "synthetic-account")
    }

    func testHeaderPreservesBodyBindingsAndKeepsPersistentSideEffects() throws {
        let source = makeSource(header: "<js>java.put('nonce','next'); result = {'X-Nonce':java.get('nonce')};</js>")
        let context = RuleExecutionContext(initialValues: ["result": "original-body", "html": "original-html"], source: source)
        let runtime = context.jsRuntime(ajaxHandler: { _ in "" })
        runtime.context.setObject("original-body", forKeyedSubscript: "result" as NSString)
        runtime.context.setObject("original-html", forKeyedSubscript: "html" as NSString)
        XCTAssertEqual(try SourceScriptHeaderResolver.evaluate(source: source, context: context).get()?["X-Nonce"], "next")
        XCTAssertEqual(context.string(for: "result"), "original-body")
        XCTAssertEqual(runtime.context.objectForKeyedSubscript("result")?.toString(), "original-body")
        XCTAssertEqual(runtime.context.objectForKeyedSubscript("html")?.toString(), "original-html")
        XCTAssertEqual(context.persistentSnapshot()["nonce"], "next")
    }

    func testHeaderBootstrapSkipsRecursiveEvaluationAndClearsGuard() throws {
        let source = makeSource(header: "@js: var token = java.ajax('https://header.fixture.invalid/bootstrap').body(); JSON.stringify({'X-Token':token});")
        let context = RuleExecutionContext(source: source)
        var bootstrapCount = 0
        context.responseHandler = { _ in
            bootstrapCount += 1
            do { XCTAssertNil(try SourceScriptHeaderResolver.evaluate(source: source, context: context).get()) }
            catch { XCTFail("Recursive bootstrap returned an error instead of omitting its pending header") }
            return SourceResponse(url: URL(string: source.bookSourceUrl)!, statusCode: 200,
                headers: [:], body: "synthetic-token", data: Data("synthetic-token".utf8))
        }
        defer { context.responseHandler = nil }
        for _ in 0..<2 {
            XCTAssertEqual(try SourceScriptHeaderResolver.evaluate(source: source, context: context).get()?["X-Token"], "synthetic-token")
        }
        XCTAssertEqual(bootstrapCount, 2)
    }

    func testInvalidOutputsFailWithoutExposingValues() {
        let scripts = [
            "throw new Error('fixture-private-value')", "''", "null", "[]",
            "({'X-Nested':{secret:'fixture-private-value'}})",
            "({'Bad Name':'fixture-private-value'})", "({'X-Test':'a\\r\\nb'})",
            "({'X-Test':'a', 'x-test':'b'})", "({'X-Test':'a'.repeat(8193)})",
            "JSON.stringify({'X-Test':'a'.repeat(65537)})"
        ]
        for script in scripts {
            let source = makeSource(header: "@js: " + script)
            let outcome = SourceScriptHeaderResolver.evaluate(source: source, context: RuleExecutionContext(source: source))
            guard case .failure(let error) = outcome else { XCTFail("Malformed header was accepted"); continue }
            XCTAssertFalse(error.localizedDescription.contains("fixture-private-value"))
        }
    }

    func testBootstrapFailureCannotBecomeAnEmptyHeaderSuccess() {
        let source = makeSource(header: "@js: java.ajax('https://header.fixture.invalid/bootstrap'); JSON.stringify({});")
        let context = RuleExecutionContext(source: source)
        context.responseHandler = { _ in
            context.recordScriptRequestFailure(.network("Synthetic bootstrap failed"))
            return .noHTTPResponse
        }
        defer { context.responseHandler = nil }
        guard case .failure = SourceScriptHeaderResolver.evaluate(source: source, context: context) else {
            return XCTFail("Failed bootstrap was silently replaced by empty headers")
        }
    }

    func testExplicitEmptyObjectAndScalarValuesAreSupported() throws {
        let empty = makeSource(header: "@js: JSON.stringify({});")
        XCTAssertEqual(try SourceScriptHeaderResolver.evaluate(source: empty, context: RuleExecutionContext(source: empty)).get(), [:])
        let numeric = makeSource(header: "@js: ({'X-Count':2, 'X-Empty':''})")
        XCTAssertEqual(try SourceScriptHeaderResolver.evaluate(source: numeric, context: RuleExecutionContext(source: numeric)).get(),
            ["X-Count": "2", "X-Empty": ""])
    }

    func testAjaxHeaderPreservesOuterObjectsAndLoginMapIdentity() throws {
        let source = makeSource(header: "@js: result = {'X-Account':source.getLoginInfoMap().get('account')};")
        let context = RuleExecutionContext(source: source)
        context.put("synthetic-account", for: SourceLoginScript.loginInfoKey("account"))
        context.responseHandler = { _ in
            do {
                let headers = try SourceScriptHeaderResolver.evaluate(source: source, context: context).get()
                XCTAssertEqual(headers?["X-Account"], "synthetic-account")
            } catch { XCTFail("Nested header evaluation failed") }
            return SourceResponse(url: URL(string: source.bookSourceUrl)!, statusCode: 200,
                headers: [:], body: "synthetic-response", data: Data("synthetic-response".utf8))
        }
        defer { context.responseHandler = nil }
        let runtime = context.jsRuntime(ajaxHandler: { _ in "" })
        let result = try runtime.evaluate("""
        var savedSource = source, savedBook = book, savedChapter = chapter;
        var savedResult = result, savedHTML = html, savedSrc = src;
        var savedDocument = __legadoRuleDocument;
        var loginMap = source.getLoginInfoMap();
        java.ajax(source.bookSourceUrl + '/bootstrap');
        JSON.stringify({source:source === savedSource, book:book === savedBook, chapter:chapter === savedChapter,
          result:result === savedResult, html:html === savedHTML, src:src === savedSrc,
          document:__legadoRuleDocument === savedDocument, key:key, page:page,
          account:loginMap.get('account'), currentAccount:source.getLoginInfoMap().get('account')});
        """, variables: ["source": source, "book": ["name": "Book"], "chapter": ["title": "Chapter"],
            "result": ["body": "original"], "html": "original-html", "src": "original-src",
            "key": "original-key", "page": 3, JSCoreRuntime.ruleDocumentBinding: ["document": "original"]]).get()
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
        for key in ["source", "book", "chapter", "result", "html", "src", "document"] {
            XCTAssertEqual(fields[key] as? Bool, true, key)
        }
        XCTAssertEqual(fields["key"] as? String, "original-key")
        XCTAssertEqual(fields["page"] as? Int, 3)
        XCTAssertEqual(fields["account"] as? String, "synthetic-account")
        XCTAssertEqual(fields["currentAccount"] as? String, "synthetic-account")
    }

    func testLibraryTopLevelAjaxBootstrapsOnceBeforeHeaderFunctionExists() throws {
        let source = makeSource(header: "@js: JSON.stringify(buildHeaders());", library: """
        java.put('libraryRuns', Number(java.get('libraryRuns') || 0) + 1);
        java.ajax(source.bookSourceUrl + '/bootstrap');
        var buildHeaders = function() { return {'X-Library':'ready'}; };
        """)
        let context = RuleExecutionContext(source: source)
        var bootstrapCount = 0
        context.responseHandler = { _ in
            bootstrapCount += 1
            do { XCTAssertNil(try SourceScriptHeaderResolver.evaluate(source: source, context: context).get()) }
            catch { XCTFail("Library initialization tried to invoke an unavailable header function") }
            return SourceResponse(url: URL(string: source.bookSourceUrl)!, statusCode: 200,
                headers: [:], body: "synthetic-bootstrap", data: Data("synthetic-bootstrap".utf8))
        }
        defer { context.responseHandler = nil }
        let runtime = context.jsRuntime(ajaxHandler: { _ in "" })
        XCTAssertEqual(try runtime.evaluate("'rule-ready'", variables: ["source": source, "baseUrl": source.cleanSourceURL]).get(), "rule-ready")
        XCTAssertEqual(try SourceScriptHeaderResolver.evaluate(source: source, context: context).get()?["X-Library"], "ready")
        XCTAssertEqual(bootstrapCount, 1)
        XCTAssertEqual(context.string(for: "libraryRuns"), "1")
    }

    func testHeaderLocalDeclarationsDoNotOverwriteOuterJavaScriptGlobals() throws {
        let source = makeSource(header: """
        @js:
        var token = 'header-token';
        function outerFunction() { return 'header-function'; }
        java.put('savedHeaderToken', token);
        JSON.stringify({'X-Token':token, 'X-This':this === globalThis ? 'global' : 'wrong'});
        """)
        let context = RuleExecutionContext(source: source)
        context.responseHandler = { _ in
            do {
                let headers = try SourceScriptHeaderResolver.evaluate(source: source, context: context).get()
                XCTAssertEqual(headers?["X-Token"], "header-token")
                XCTAssertEqual(headers?["X-This"], "global")
            } catch { XCTFail("Isolated header evaluation failed") }
            return SourceResponse(url: URL(string: source.bookSourceUrl)!, statusCode: 200,
                headers: [:], body: "synthetic-response", data: Data("synthetic-response".utf8))
        }
        defer { context.responseHandler = nil }
        let runtime = context.jsRuntime(ajaxHandler: { _ in "" })
        let result = try runtime.evaluate("""
        var token = 'outer-token';
        function outerFunction() { return 'outer-function'; }
        java.ajax(source.bookSourceUrl + '/bootstrap');
        token + '|' + outerFunction() + '|' + java.get('savedHeaderToken');
        """, variables: ["source": source]).get()
        XCTAssertEqual(result, "outer-token|outer-function|header-token")
    }

    func testIsolatedHeaderKeepsTheExistingAwaitNormalization() throws {
        let source = makeSource(header: "@js: let nonce = await java.ajax('https://header.fixture.invalid/bootstrap'); JSON.stringify({'X-Nonce':nonce.body()});")
        let context = RuleExecutionContext(source: source)
        context.responseHandler = { _ in
            SourceResponse(url: URL(string: source.bookSourceUrl)!, statusCode: 200,
                headers: [:], body: "normalized-nonce", data: Data("normalized-nonce".utf8))
        }
        defer { context.responseHandler = nil }
        XCTAssertEqual(try SourceScriptHeaderResolver.evaluate(source: source, context: context).get()?["X-Nonce"], "normalized-nonce")
    }

    private func makeSource(header: String, library: String = "") -> BookSource {
        BookSource(bookSourceName: "Synthetic header fixture", bookSourceUrl: "https://header.fixture.invalid/",
            header: header, raw: ["jsLib": library])
    }
}
