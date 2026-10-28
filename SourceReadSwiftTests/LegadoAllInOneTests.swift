import XCTest
@testable import SourceReadSwift

/// Legado list-level AllInOne regex (`chapterList: ":pattern"`).
///
/// The official syntax guide's second sample source uses this shape:
/// `":href=\\"(/read[^\\"]*html)\\">([^<]*)"` with `chapterName: "$2"` and
/// `chapterUrl: "$1"`. Before this suite the rule was handed to the CSS
/// selector engine and produced zero chapters.
final class LegadoAllInOneTests: XCTestCase {
    func testTocAllInOneRegexBuildsChaptersFromCaptureGroups() throws {
        let source = BookSource(
            bookSourceName: "AllInOne TOC",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": #":href="(/read[^"]*html)">([^<]*)"#,
                "chapterName": "$2",
                "chapterUrl": "$1"
            ])
        )
        let body = """
        <html><body><div class="list">
        <a href="/read/1.html">第一章</a>
        <a href="/read/2.html">第二章</a>
        </div></body></html>
        """
        let response = SourceResponse(
            url: URL(string: "https://fixture.example/book/1")!,
            statusCode: 200,
            headers: [:],
            body: body,
            data: Data()
        )

        let chapters = try ChapterListParser().parse(
            source: source,
            book: makeBook(tocURL: "https://fixture.example/book/1"),
            response: response
        ).get()

        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(chapters.map(\.url), [
            "https://fixture.example/read/1.html",
            "https://fixture.example/read/2.html"
        ])
    }

    func testTocAllInOneReversePrefixReversesRows() throws {
        let source = BookSource(
            bookSourceName: "AllInOne TOC reversed",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": #"-:href="(/read[^"]*html)">([^<]*)"#,
                "chapterName": "$2",
                "chapterUrl": "$1"
            ])
        )
        let body = """
        <a href="/read/1.html">第一章</a>
        <a href="/read/2.html">第二章</a>
        """
        let response = SourceResponse(
            url: URL(string: "https://fixture.example/book/1")!,
            statusCode: 200,
            headers: [:],
            body: body,
            data: Data()
        )

        let chapters = try ChapterListParser().parse(
            source: source,
            book: makeBook(tocURL: "https://fixture.example/book/1"),
            response: response
        ).get()

        XCTAssertEqual(chapters.map(\.title), ["第二章", "第一章"])
    }

    func testSearchAllInOneRegexBuildsBooks() throws {
        let source = BookSource(
            bookSourceName: "AllInOne search",
            bookSourceUrl: "https://fixture.example",
            ruleSearch: SourceRule(fields: [
                "bookList": #":href="(/book/\d+)"[^>]*>([^<]+)<"#,
                "name": "$2",
                "bookUrl": "$1"
            ])
        )
        let body = """
        <html><body>
        <a href="/book/7">书七</a>
        <a href="/book/9">书九</a>
        </body></html>
        """
        let response = SourceResponse(
            url: URL(string: "https://fixture.example/search?q=x")!,
            statusCode: 200,
            headers: [:],
            body: body,
            data: Data()
        )

        let books = try SearchResultParser().parse(source: source, response: response).get()

        XCTAssertEqual(books.map(\.name), ["书七", "书九"])
        XCTAssertEqual(books.map(\.bookUrl), [
            "https://fixture.example/book/7",
            "https://fixture.example/book/9"
        ])
    }

    func testAllInOneRuleParsingRejectsPlainSelectors() {
        XCTAssertNil(LegadoAllInOneRegex.rule(from: ".chapter a"))
        XCTAssertNil(LegadoAllInOneRegex.rule(from: "-.chapter a"))
        XCTAssertEqual(LegadoAllInOneRegex.rule(from: #"-:href="([^"]+)""#)?.reversed, true)
        XCTAssertEqual(LegadoAllInOneRegex.rule(from: #":href="([^"]+)""#)?.reversed, false)
    }

    private func makeBook(tocURL: String) -> BookDetail {
        BookDetail(
            name: "Fixture Book",
            author: "Fixture Author",
            coverUrl: nil,
            bookUrl: "https://fixture.example/book/fixture",
            tocUrl: tocURL,
            sourceName: "Fixture",
            sourceUrl: "https://fixture.example",
            intro: nil,
            latestChapter: nil
        )
    }
}
