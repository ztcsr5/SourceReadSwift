import XCTest
@testable import SourceReadSwift
import SwiftSoup

final class RuleExtractorJSTests: XCTestCase {
    func testHtmlRuleExtractorEvaluatesJavaScriptRule() throws {
        let html = """
        <html><body>
          <div class="book">
            <span class="price">120元</span>
          </div>
        </body></html>
        """
        let document = try SwiftSoup.parse(html)
        let extractor = HtmlRuleExtractor()
        
        // 规则是一个以 @js: 开头的 JS 规则，需要剥离 outerHtml 的标签
        let rule = "@js: result.replace('元', '').replace(/<[^>]+>/g, '')"
        let val = try extractor.value(from: document.select(".price").first!, rule: rule)
        XCTAssertEqual(val, "120")
    }

    func testJSONRuleExtractorEvaluatesJavaScriptRule() throws {
        let jsonStr = #"{"name": "斗破苍穹", "tags": ["玄幻", "热血"]}"#
        let data = jsonStr.data(using: .utf8)!
        let object = try JSONSerialization.jsonObject(with: data)
        let extractor = JSONRuleExtractor()
        
        // 规则是一个 JS 规则
        let rule = "@js: result.tags.join('-')"
        let val = extractor.value(from: object, path: rule) as? String
        XCTAssertEqual(val, "玄幻-热血")
    }

    func testDynamicURLResolverJinjiangTemplate() throws {
        let source = BookSource(
            bookSourceName: "晋江文学",
            bookSourceUrl: "https://m.jjwxc.net/channel",
            bookSourceType: 0
        )
        let rawURL = "http://app-cdn.jjwxc.net/androidapi/chapterList?novelId={{baseUrl.match(/novelId=(\\d+)/)[1]}}&more=0&whole=1"
        let baseUrl = "https://www.jjwxc.net/onebook.php?novelid=7322952"
        let context = RuleExecutionContext(source: source)
        let resolved = DynamicURLResolver.resolve(
            rawURL,
            baseUrl: baseUrl,
            source: source,
            variables: [:],
            context: context
        )
        XCTAssertEqual(resolved, "http://app-cdn.jjwxc.net/androidapi/chapterList?novelId=7322952&more=0&whole=1")
    }

    func testChapterListParserFiltersDummyAnchorsAndRecovers() throws {
        let html = """
        <html><body>
          <div class="chapter-list">
            <a href="!">倒序</a>
          </div>
          <div class="dir-list">
            <a href="/book/100/1.html">第一章 初始</a>
            <a href="/book/100/2.html">第二章 进展</a>
          </div>
        </body></html>
        """
        let source = BookSource(
            bookSourceName: "篱笆测试",
            bookSourceUrl: "https://m.libahao.com",
            ruleToc: SourceRule(fields: [
                "chapterList": ".chapter-list.1@a",
                "chapterName": "text",
                "chapterUrl": "href"
            ])
        )
        let book = BookDetail(
            name: "测试书",
            author: nil,
            coverUrl: nil,
            bookUrl: "https://m.libahao.com/book/100/",
            tocUrl: nil,
            sourceName: source.bookSourceName,
            sourceUrl: source.bookSourceUrl,
            intro: nil,
            latestChapter: nil
        )
        let response = SourceResponse(
            url: URL(string: "https://m.libahao.com/book/100/")!,
            statusCode: 200,
            headers: ["Content-Type": "text/html"],
            body: html,
            data: Data(html.utf8)
        )
        let result = ChapterListParser().parse(source: source, book: book, response: response)
        switch result {
        case .success(let chapters):
            XCTAssertEqual(chapters.count, 2)
            XCTAssertEqual(chapters[0].title, "第一章 初始")
            XCTAssertEqual(chapters[0].url, "https://m.libahao.com/book/100/1.html")
        case .failure(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
}
