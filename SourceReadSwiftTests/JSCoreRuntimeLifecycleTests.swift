import XCTest
@testable import SourceReadSwift

/// A source shares its library and @put store, not a rule's let/const scope.
final class JSCoreRuntimeLifecycleTests: XCTestCase {
    func testRepeatedRulesHaveIndependentLexicalBindings() throws {
        let runtime = JSCoreRuntime()
        for index in 1...3 {
            let output = try runtime.evaluate(
                "let data = result; const title = data.title; title",
                variables: ["result": ["title": "Chapter \(index)"]]
            ).get()
            XCTAssertEqual(output, "Chapter \(index)")
        }
    }

    func testRuleVarAndFunctionsRemainShared() throws {
        let runtime = JSCoreRuntime()
        _ = try runtime.evaluate("var bookId = '765'; function currentBookId() { return bookId; }").get()
        XCTAssertEqual(try runtime.evaluate("currentBookId()").get(), "765")
        _ = try runtime.evaluate("bookId = '766'").get()
        XCTAssertEqual(try runtime.evaluate("currentBookId()").get(), "766")
    }

    func testRuleCompletionAndStrictModeArePreserved() throws {
        let runtime = JSCoreRuntime()
        XCTAssertEqual(try runtime.evaluate("if (true) { 'chapter'; }").get(), "chapter")
        XCTAssertThrowsError(try runtime.evaluate("'use strict'; unknownStrictGlobal = 1").get())
    }

    func testLibraryInitializersSeeBoundSourceAndAllRuleGlobals() throws {
        let source = BookSource(
            bookSourceName: "Bound library",
            bookSourceUrl: "https://fixture.test",
            raw: ["jsLib": """
            let libraryHost = source.bookSourceUrl;
            let libraryBase = baseUrl;
            let libraryKey = key;
            let libraryBook = book.name;
            function libraryValues() { return [libraryHost, libraryBase, libraryKey, libraryBook].join('|'); }
            """]
        )
        let context = RuleExecutionContext(source: source)
        let runtime = context.jsRuntime(ajaxHandler: { _ in "" })
        XCTAssertEqual(try runtime.evaluate("libraryValues()", variables: [
            "baseUrl": "https://fixture.test/search",
            "key": "fixture",
            "book": ["name": "First book"]
        ]).get(), "https://fixture.test|https://fixture.test/search|fixture|First book")
        // The next field must not reinitialize a library's const/let globals.
        XCTAssertEqual(try runtime.evaluate("libraryValues()", variables: ["key": "second"]).get(),
                       "https://fixture.test|https://fixture.test/search|fixture|First book")
    }

    func testRuleCanShadowLibraryLexicalBindingWithoutPoisoningNextRule() throws {
        let source = BookSource(bookSourceName: "Shadow", bookSourceUrl: "https://fixture.test",
                                raw: ["jsLib": "let data = 'library'; function libraryData() { return data; }"])
        let runtime = RuleExecutionContext(source: source).jsRuntime(ajaxHandler: { _ in "" })
        XCTAssertEqual(try runtime.evaluate("let data = 'row'; data").get(), "row")
        XCTAssertEqual(try runtime.evaluate("libraryData()").get(), "library")
    }

    func testConstCannotBeReassignedAndBlockLetDoesNotEscape() throws {
        let runtime = JSCoreRuntime()
        XCTAssertThrowsError(try runtime.evaluate("const value = 1; value = 2; value").get())
        XCTAssertEqual(try runtime.evaluate("if (true) { let row = 'inside'; } typeof row").get(), "undefined")
        XCTAssertEqual(try runtime.evaluate("'after failed const'").get(), "after failed const")
    }

    func testSourceNamedLexicalVariableInSearchRowDoesNotConflictWithSourceBridge() throws {
        // 76-source corpus #13 书山聚合 declares `let source = result.source`
        // in its per-row bookUrl rule. The global source facade is a var;
        // evaluateScript rejects this even on the FIRST row.
        let source = BookSource(bookSourceName: "Row source", bookSourceUrl: "https://fixture.test")
        let context = RuleExecutionContext(source: source)
        let extractor = JSONRuleExtractor(executionContext: context)
        for id in ["one", "two"] {
            let row: [String: Any] = ["source": "provider", "book_url": id]
            let output = extractor.string(from: row, rule: "<js>let source = String(result.source); let book_url = result.book_url; source + '/' + book_url;</js>", variables: ["source": source])
            XCTAssertEqual(output, "provider/" + id)
            XCTAssertNil(context.currentJavaScriptError)
        }
    }

    func testLibraryFailureIsReportedAndNotSilentlyCachedAsSuccess() {
        let source = BookSource(bookSourceName: "Broken library", bookSourceUrl: "https://fixture.test",
                                raw: ["jsLib": "java.put('libraryAttempts', Number(java.get('libraryAttempts') || 0) + 1); throw new Error('library failed');"])
        let context = RuleExecutionContext(source: source)
        let runtime = context.jsRuntime(ajaxHandler: { _ in "" })
        for _ in 0..<2 {
            switch runtime.evaluate("'must not execute'") {
            case .success:
                XCTFail("A failed library must fail the dependent rule")
            case .failure(let error):
                XCTAssertTrue(error.displayMessage.contains("library failed"))
            }
        }
        XCTAssertEqual(context.get("libraryAttempts"), "1", "Do not replay failed initialization side effects")
    }
}
