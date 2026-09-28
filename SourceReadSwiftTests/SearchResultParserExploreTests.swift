import XCTest
@testable import SourceReadSwift

final class SearchResultParserExploreTests: XCTestCase {

    func testParseWithRuleExploreOverride() {
        let html = """
        <html>
        <body>
            <div class="explore-list">
                <div class="explore-card">
                    <a class="tit" href="/book/101.html">星门传说</a>
                    <span class="auth">老鹰吃小鸡</span>
                    <img src="/cover/101.jpg" />
                    <p class="desc">热血仙侠巨作</p>
                </div>
            </div>
        </body>
        </html>
        """

        let source = BookSource(
            bookSourceName: "测试书源",
            bookSourceUrl: "https://example.com",
            ruleSearch: SourceRule(fields: [
                "bookList": ".search-card",
                "name": ".title@text",
                "author": ".author@text",
                "bookUrl": "a@href"
            ]),
            ruleExplore: SourceRule(fields: [
                "bookList": ".explore-card",
                "name": "a.tit@text",
                "author": "span.auth@text",
                "bookUrl": "a.tit@href",
                "coverUrl": "img@src",
                "intro": "p.desc@text"
            ])
        )

        let response = SourceResponse(
            url: URL(string: "https://example.com/explore")!,
            statusCode: 200,
            headers: [:],
            body: html
        )

        let parser = SearchResultParser()
        let result = parser.parse(source: source, response: response, ruleOverride: source.ruleExplore)

        guard case .success(let books) = result else {
            XCTFail("Expected success but got \(result)")
            return
        }

        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].name, "星门传说")
        XCTAssertEqual(books[0].author, "老鹰吃小鸡")
        XCTAssertEqual(books[0].bookUrl, "https://example.com/book/101.html")
        XCTAssertEqual(books[0].coverUrl, "https://example.com/cover/101.jpg")
    }

    func testParseWithRuleExploreFallbackToRuleSearch() {
        let html = """
        <html>
        <body>
            <div class="explore-card">
                <a class="tit" href="/book/202.html">剑来</a>
                <span class="fallback-author">烽火戏诸侯</span>
            </div>
        </body>
        </html>
        """

        // ruleExplore does not define "author", so it should fall back to ruleSearch's definition for author
        let source = BookSource(
            bookSourceName: "测试书源",
            bookSourceUrl: "https://example.com",
            ruleSearch: SourceRule(fields: [
                "bookList": ".search-card",
                "name": "a.tit@text",
                "author": ".fallback-author@text",
                "bookUrl": "a.tit@href"
            ]),
            ruleExplore: SourceRule(fields: [
                "bookList": ".explore-card",
                "name": "a.tit@text",
                "bookUrl": "a.tit@href"
            ])
        )

        let response = SourceResponse(
            url: URL(string: "https://example.com/explore")!,
            statusCode: 200,
            headers: [:],
            body: html
        )

        let parser = SearchResultParser()
        let result = parser.parse(source: source, response: response, ruleOverride: source.ruleExplore)

        guard case .success(let books) = result else {
            XCTFail("Expected success but got \(result)")
            return
        }

        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].name, "剑来")
        XCTAssertEqual(books[0].author, "烽火戏诸侯")
    }
}
