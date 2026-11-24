import XCTest
@testable import SourceReadSwift

final class SearchResultParserTests: XCTestCase {
    func testMowanInlineBookAddressesRemainIntactWithAndWithoutBase64Padding() throws {
        let paths = [
            "/api/book/detail?source=fixture-novel&book_id=book-fixture-1",
            "/api/book/detail?source=fixture-novel&book_id=book-fixture-12"
        ]
        let addresses = paths.map { "data:;base64," + Data($0.utf8).base64EncodedString() + #",{"type":"mw"}"# }
        XCTAssertFalse(addresses[0].contains("="))
        XCTAssertTrue(addresses[1].contains("="))
        let rows = addresses.enumerated().map { index, address in
            ["name": "Fixture \(index)", "url": address, "id": "book-fixture-\(index)", "source": "fixture-novel"]
        }
        let body = try XCTUnwrap(String(
            data: JSONSerialization.data(withJSONObject: ["items": rows]), encoding: .utf8
        ))
        let source = BookSource(bookSourceName: "Mowan inline fixture", bookSourceUrl: "https://mowan.fixture.invalid",
            ruleSearch: SourceRule(fields: ["bookList": "$.items", "name": "name", "bookUrl": "url"]))
        let response = SourceResponse(url: URL(string: "https://mowan.fixture.invalid/api/search")!, statusCode: 200,
            headers: ["Content-Type": "application/json"], body: body, data: Data())

        let books = try SearchResultParser().parse(source: source, response: response).get()

        XCTAssertEqual(books.map(\.bookUrl), addresses)
    }

    func testMowanBareBookIDStillUsesTheDetailAddress() throws {
        let source = BookSource(bookSourceName: "Mowan ID fixture", bookSourceUrl: "https://mowan.fixture.invalid",
            ruleSearch: SourceRule(fields: ["bookList": "$.items", "name": "name", "bookUrl": "id"]))
        let response = SourceResponse(url: URL(string: "https://mowan.fixture.invalid/api/search")!, statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: #"{"items":[{"name":"Fixture","id":"book-fixture-1","source":"fixture-novel"}]}"#, data: Data())

        let books = try SearchResultParser().parse(source: source, response: response).get()

        XCTAssertEqual(books.map(\.bookUrl), [
            "https://www.mowan.lol/api/book/detail?source=fixture-novel&book_id=book-fixture-1"
        ])
    }

    func testBareJavaSelectionBindsFieldSelectorsToEachRow() throws {
        let source = BookSource(bookSourceName: "Bare script fixture", bookSourceUrl: "https://fixture.example",
            ruleSearch: SourceRule(fields: [
                "bookList": "java.getElements('.book')",
                "name": "@js:java.getString('a@text')",
                "bookUrl": "@js:java.getString('a@href')"
            ]))
        let response = SourceResponse(url: URL(string: "https://fixture.example/search")!, statusCode: 200,
            headers: [:], body: """
                <div class="book"><a href="/book/1">One</a></div>
                <div class="book"><a href="/book/2">Two</a></div>
                """, data: Data())
        let books = try SearchResultParser().parse(source: source, response: response).get()
        XCTAssertEqual(books.map(\.name), ["One", "Two"])
        XCTAssertEqual(books.map(\.bookUrl), ["https://fixture.example/book/1", "https://fixture.example/book/2"])
    }

    func testHTMLReturningSearchScriptExecutesOnce() throws {
        let fixture = parseSelectionFixture(list: """
            @js:java.put('calls', Number(java.get('calls') || 0) + 1);
            '<div class="book"><a href="/book/1">Title</a></div>';
            """)
        XCTAssertEqual(try fixture.outcome.get().map(\.name), ["Title"])
        XCTAssertEqual(fixture.context.persistentSnapshot()["calls"], "1")
    }

    func testNativeSearchSelectionExecutesOnce() throws {
        let fixture = parseSelectionFixture(list: """
            @js:java.put('calls', Number(java.get('calls') || 0) + 1);
            java.getElements('class.book');
            """, body: #"<div class="book"><a href="/book/1">Title</a></div>"#)
        XCTAssertEqual(try fixture.outcome.get().map(\.name), ["Title"])
        XCTAssertEqual(fixture.context.persistentSnapshot()["calls"], "1")
    }

    func testBoxedStringSearchSelectionKeepsJSONTextWithoutRepeatingItsScript() throws {
        let fixture = parseSelectionFixture(list: """
            <js>java.put('calls', Number(java.get('calls') || 0) + 1);
            new String(JSON.stringify([{name: 'Title', url: '/book/1'}]));</js>$[*]
            """, jsonFields: true)
        XCTAssertEqual(try fixture.outcome.get().map(\.name), ["Title"])
        XCTAssertEqual(fixture.context.persistentSnapshot()["calls"], "1")
    }

    func testLegacyMapNumericCaptureBuildsDetailURLsFromJSONRows() throws {
        let source = BookSource(bookSourceName: "Map identifier fixture", bookSourceUrl: "https://fixture.example",
            ruleSearch: SourceRule(fields: [
                "bookList": "<js>JSON.stringify(JSON.parse(result).items)</js>$.[*]",
                "name": "$.name",
                "bookUrl": #"""
                    <js>
                    id = String(result).match(/id=(\d+)/)[1];
                    (String(result).match(/drama_id/) ? '/episode/' : '/book/') + id;
                    </js>
                    """#
            ]))
        let body = #"{"items":[{"id":1042,"name":"Book"},{"id":"00729","drama_id":1042,"name":"Episode"},{"drama_id":77,"name":"Missing ID"}]}"#
        let response = SourceResponse(url: try XCTUnwrap(URL(string: "https://fixture.example/search")), statusCode: 200,
            headers: ["Content-Type": "application/json"], body: body, data: Data(body.utf8))

        let books = try SearchResultParser().parse(source: source, response: response).get()

        XCTAssertEqual(books.map(\.name), ["Book", "Episode"])
        XCTAssertEqual(books.map(\.bookUrl), ["https://fixture.example/book/1042", "https://fixture.example/episode/00729"])
    }

    func testHTMLSelectionCanBecomeJSONWithoutRepeatingItsScript() throws {
        let fixture = parseSelectionFixture(list: """
            .book<js>java.put('calls', Number(java.get('calls') || 0) + 1);
            JSON.stringify([{name: result.get(0).text(), url: '/book/1'}]);</js>$[*]
            """, body: #"<div class="book"><a href="/book/1">Title</a></div>"#, jsonFields: true)
        XCTAssertEqual(try fixture.outcome.get().map(\.name), ["Title"])
        XCTAssertEqual(fixture.context.persistentSnapshot()["calls"], "1")
    }

    func testJSONSelectionCanBecomeHTMLWithoutRepeatingItsScript() throws {
        let fixture = parseSelectionFixture(list: """
            $.markup<js>java.put('calls', Number(java.get('calls') || 0) + 1); result;</js>.book
            """, body: #"{"markup":"<div class='book'><a href='/book/1'>Title</a></div>"}"#)
        XCTAssertEqual(try fixture.outcome.get().map(\.name), ["Title"])
        XCTAssertEqual(fixture.context.persistentSnapshot()["calls"], "1")
    }

    func testSearchInitializationRunsOnceAndKeepsOriginalResponseBindings() throws {
        let fixture = parseSelectionFixture(list: """
            @js:java.put('calls', Number(java.get('calls') || 0) + 1);
            java.put('original', src.includes('Original') && html.includes('Original'));
            java.getElements('class.book');
            """, initialization: """
            @js:java.put('initializations', Number(java.get('initializations') || 0) + 1);
            '<div class="book"><a href="/book/1">Initialized</a></div>';
            """)
        XCTAssertEqual(try fixture.outcome.get().map(\.name), ["Initialized"])
        XCTAssertEqual(fixture.context.persistentSnapshot()["initializations"], "1")
        XCTAssertEqual(fixture.context.persistentSnapshot()["calls"], "1")
        XCTAssertEqual(fixture.context.persistentSnapshot()["original"], "true")
    }

    func testExplicitEmptySearchSelectionsAreNotReplayed() {
        for completion in ["[]", "null", "undefined", "java.getElements('.missing')"] {
            let fixture = parseSelectionFixture(list: """
                @js:java.put('calls', Number(java.get('calls') || 0) + 1); \(completion);
                """)
            guard case .failure(.empty) = fixture.outcome else {
                XCTFail("Expected an empty selection for \(completion)")
                continue
            }
            XCTAssertEqual(fixture.context.persistentSnapshot()["calls"], "1", completion)
        }
    }

    func testSearchRuntimeErrorDoesNotReplayEvenWhenAFunctionContainsReturn() {
        let fixture = parseSelectionFixture(list: """
            @js:function unused() { return 1; }
            java.put('calls', Number(java.get('calls') || 0) + 1);
            throw new Error('Selection fixture failed');
            """)
        guard case .failure(.javascript(let message)) = fixture.outcome else {
            return XCTFail("Expected the original JavaScript error")
        }
        XCTAssertTrue(message.contains("Selection fixture failed"))
        XCTAssertEqual(fixture.context.persistentSnapshot()["calls"], "1")
    }

    func testTopLevelReturnAndReverseSearchModifierRemainSupported() throws {
        for modifier in ["+", "-"] {
            let fixture = parseSelectionFixture(list: """
                \(modifier)@js:java.put('calls', Number(java.get('calls') || 0) + 1);
                return [{name:'One',url:'/book/1'},{name:'Two',url:'/book/2'}];
                """, jsonFields: true)
            XCTAssertEqual(try fixture.outcome.get().map(\.name), modifier == "-" ? ["Two", "One"] : ["One", "Two"])
            XCTAssertEqual(fixture.context.persistentSnapshot()["calls"], "1")
        }
    }

    func testRuntimeThrownReturnSyntaxErrorDoesNotReplaySearchScript() {
        let fixture = parseSelectionFixture(list: """
            @js:java.put('calls', Number(java.get('calls') || 0) + 1);
            throw new SyntaxError('Return statements are only valid inside functions');
            """)
        guard case .failure(.javascript) = fixture.outcome else {
            return XCTFail("Expected the runtime-thrown SyntaxError")
        }
        XCTAssertEqual(fixture.context.persistentSnapshot()["calls"], "1")
    }

    private func parseSelectionFixture(
        list: String,
        body: String = "<html><body><p>Original</p></body></html>",
        initialization: String? = nil,
        jsonFields: Bool = false
    ) -> (outcome: Result<[SearchBook], SourceEngineError>, context: RuleExecutionContext) {
        let context = RuleExecutionContext()
        var fields = ["bookList": list, "name": jsonFields ? "name" : "a@text", "bookUrl": jsonFields ? "url" : "a@href"]
        if let initialization { fields["init"] = initialization }
        let source = BookSource(bookSourceName: "Selection fixture", bookSourceUrl: "https://fixture.example",
                                ruleSearch: SourceRule(fields: fields))
        let response = SourceResponse(url: URL(string: "https://fixture.example/search")!, statusCode: 200,
                                      headers: [:], body: body, data: Data())
        return (SearchResultParser(executionContext: context).parse(source: source, response: response), context)
    }

    func testJavaGetElementBookListKeepsEveryReturnedRowAfterReplacingContent() throws {
        let source = BookSource(bookSourceName: "Native list fixture", bookSourceUrl: "https://fixture.example",
            ruleSearch: SourceRule(fields: [
                "bookList": """
                    @js:java.setContent('<ol class="book-ol book-ol-normal"><li><a href="/book/1">One</a></li><li><a href="/book/2">Two</a></li></ol>');
                    java.getElement('class.book-ol book-ol-normal@tag.li');
                    """,
                "name": "tag.a@text", "bookUrl": "tag.a@href"
            ]))
        let response = SourceResponse(url: URL(string: "https://fixture.example/search")!, statusCode: 200,
            headers: [:], body: "<html><body><p>Old search page</p></body></html>", data: Data())
        let books = try SearchResultParser().parse(source: source, response: response).get()
        XCTAssertEqual(books.map(\.name), ["One", "Two"])
        XCTAssertEqual(books.map(\.bookUrl), ["https://fixture.example/book/1", "https://fixture.example/book/2"])
    }

    func testHTMLSearchAbsolutizesRelativeCoverURL() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            ruleSearch: SourceRule(fields: [
                "bookList": ".book",
                "name": ".title@text",
                "bookUrl": "a@href",
                "coverUrl": "img@src"
            ])
        )
        let response = SourceResponse(
            url: URL(string: "https://example.com/search?q=a")!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <div class="book">
                <a class="title" href="/book/1">Title</a>
                <img src="/covers/1.jpg">
              </div>
            </body></html>
            """,
            data: Data()
        )

        let result = SearchResultParser().parse(source: source, response: response)

        guard case .success(let books) = result, let book = books.first else {
            return XCTFail("expected parsed book")
        }
        XCTAssertEqual(book.coverUrl, "https://example.com/covers/1.jpg")
    }

    func testHTMLSearchUsesRuleAlternatives() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            ruleSearch: SourceRule(fields: [
                "bookList": ".book",
                "name": ".missing@text || .title@text",
                "bookUrl": ".missing@href || a@href"
            ])
        )
        let response = SourceResponse(
            url: URL(string: "https://example.com/search?q=a")!,
            statusCode: 200,
            headers: [:],
            body: #"<html><body><div class="book"><a class="title" href="/book/1">Title</a></div></body></html>"#,
            data: Data()
        )

        let result = SearchResultParser().parse(source: source, response: response)

        guard case .success(let books) = result, let book = books.first else {
            return XCTFail("expected parsed book")
        }
        XCTAssertEqual(book.name, "Title")
        XCTAssertEqual(book.bookUrl, "https://example.com/book/1")
    }

    func testJSONSearchResolvesAnAbsoluteURLContainingRowDirectives() throws {
        let source = BookSource(bookSourceName: "URL directive fixture", bookSourceUrl: "https://catalog.invalid",
            ruleSearch: SourceRule(fields: [
                "bookList": "<js>result;</js>$.data.lists[*]",
                "name": "$.bookName",
                "bookUrl": "@put:{id:$.id}\nhttps://catalog.invalid/detail?id=@get:{id}"
            ]))
        let body = #"{"data":{"lists":[{"bookName":"One","id":"17"},{"bookName":"Missing"},{"bookName":"Two","id":"29"}]}}"#
        let response = SourceResponse(url: try XCTUnwrap(URL(string: "https://catalog.invalid/search")),
            statusCode: 200, headers: ["Content-Type": "application/json"], body: body, data: Data(body.utf8))
        let books = try SearchResultParser().parse(source: source, response: response).get()
        XCTAssertEqual(books.map(\.name), ["One", "Two"])
        XCTAssertEqual(books.map(\.bookUrl), ["https://catalog.invalid/detail?id=17", "https://catalog.invalid/detail?id=29"])
    }

    func testHTMLSearchBookListSupportsPutDirective() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            ruleSearch: SourceRule(fields: [
                "bookList": "@put:{unused:.meta@text}.book",
                "name": ".title@text",
                "bookUrl": "a@href"
            ])
        )
        let response = SourceResponse(
            url: URL(string: "https://example.com/search?q=a")!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <span class="meta">cached</span>
              <div class="book"><a class="title" href="/book/1">Title</a></div>
            </body></html>
            """,
            data: Data()
        )

        let result = SearchResultParser().parse(source: source, response: response)

        guard case .success(let books) = result, let book = books.first else {
            return XCTFail("expected parsed book")
        }
        XCTAssertEqual(book.name, "Title")
        XCTAssertEqual(book.bookUrl, "https://example.com/book/1")
    }

    func testHTMLSearchSanitizesMultilineURL() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            ruleSearch: SourceRule(fields: [
                "bookList": ".book",
                "name": "h2 a@text",
                "bookUrl": "a@href"
            ])
        )
        let response = SourceResponse(
            url: URL(string: "https://example.com/search?q=a")!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <div class="book">
                <a href="/book/1"><img src="/1.jpg"></a>
                <h2><a href="/book/1">My Novel</a></h2>
              </div>
            </body></html>
            """,
            data: Data()
        )

        let result = SearchResultParser().parse(source: source, response: response)

        guard case .success(let books) = result, let book = books.first else {
            return XCTFail("expected parsed book")
        }
        XCTAssertEqual(book.bookUrl, "https://example.com/book/1")
        XCTAssertFalse(book.bookUrl.contains("\n"))
    }
}

