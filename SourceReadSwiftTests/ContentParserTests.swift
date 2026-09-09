import XCTest
@testable import SourceReadSwift

final class ContentParserTests: XCTestCase {
    func testHTMLContentSplitsParagraphTags() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": ".content@html"
            ])
        )
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <div class="content"><p>第一段</p><p>第二段<br>第三段</p></div>
            </body></html>
            """,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.paragraphs, ["第一段", "第二段", "第三段"])
    }

    func testHTMLContentAppliesReplaceRegex() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": ".content@html",
                "replaceRegex": "广告.*?结束##"
            ])
        )
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <div class="content"><p>正文第一段</p><p>广告这里删除结束正文第二段</p></div>
            </body></html>
            """,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.paragraphs, ["正文第一段", "正文第二段"])
    }

    func testHTMLContentAppliesGlobalPurifyRules() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": ".content@html"
            ])
        )
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <div class="content"><p>正文第一段</p><p>请收藏本站广告尾巴</p></div>
            </body></html>
            """,
            data: Data()
        )

        let result = ContentParser().parse(
            source: source,
            chapter: chapter,
            response: response,
            globalPurifyRules: ["请收藏本站.*##"]
        )

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.paragraphs, ["正文第一段"])
    }

    func testContentAppliesJavaScriptReplaceRegex() throws {
        let source = BookSource(
            bookSourceName: "TestJS",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": ".content@html",
                "replaceRegex": "<js>function x(a, b) { result = String(result).replace(a, b); } x(/#obf1#/g, '解密'); result;</js>"
            ])
        )
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <div class="content"><p>这是#obf1#文本段落</p></div>
            </body></html>
            """,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.paragraphs, ["这是解密文本段落"])
    }

    func testContentParserSuppliesSrcAndBaseUrlToJavaScriptRules() throws {
        let source = BookSource(
            bookSourceName: "TestSrc",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": "<js>if (/flag1234/.test(src)) { result = 'FoundInSrc: ' + baseUrl; } else { result = 'No'; } result;</js>"
            ])
        )
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <!-- flag1234 -->
              <div class="content"><p>原文</p></div>
            </body></html>
            """,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.paragraphs, ["FoundInSrc: https://example.com/book/1/1.html"])
    }
}
