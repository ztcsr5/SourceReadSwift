import XCTest
@testable import SourceReadSwift

final class SearchResultParserTests: XCTestCase {
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

