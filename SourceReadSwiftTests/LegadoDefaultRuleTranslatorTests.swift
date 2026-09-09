import XCTest
import SwiftSoup
@testable import SourceReadSwift

final class LegadoDefaultRuleTranslatorTests: XCTestCase {
    func testTranslateClassAndTagWithAttribute() throws {
        let rule = "class.bookbox@tag.a@href"
        let translated = LegadoDefaultRuleTranslator.translateValueRule(rule)
        XCTAssertNotNil(translated)
        XCTAssertEqual(translated?.steps.count, 2)
        XCTAssertEqual(translated?.steps[0].selector, ".bookbox")
        XCTAssertEqual(translated?.steps[1].selector, "a")
        XCTAssertEqual(translated?.attribute, "href")
    }

    func testTranslateIdTagChainWithIndex() throws {
        let rule = "id.chapterlist@tag.dd@tag.a.0@text"
        let translated = LegadoDefaultRuleTranslator.translateValueRule(rule)
        XCTAssertNotNil(translated)
        XCTAssertEqual(translated?.steps.count, 3)
        XCTAssertEqual(translated?.steps[0].selector, "#chapterlist")
        XCTAssertEqual(translated?.steps[1].selector, "dd")
        XCTAssertEqual(translated?.steps[2].selector, "a")
        XCTAssertEqual(translated?.steps[2].index, 0)
        XCTAssertEqual(translated?.attribute, "text")
    }

    func testTranslateExcludeIndex() throws {
        let rule = "class.item!0@tag.a@text"
        let translated = LegadoDefaultRuleTranslator.translateValueRule(rule)
        XCTAssertNotNil(translated)
        XCTAssertEqual(translated?.steps.count, 2)
        XCTAssertEqual(translated?.steps[0].selector, ".item")
        XCTAssertEqual(translated?.steps[0].excludeIndex, 0)
        XCTAssertEqual(translated?.steps[1].selector, "a")
        XCTAssertEqual(translated?.attribute, "text")
    }

    func testTranslateChildren() throws {
        let rule = "id.content@children@text"
        let translated = LegadoDefaultRuleTranslator.translateValueRule(rule)
        XCTAssertNotNil(translated)
        XCTAssertEqual(translated?.steps.count, 2)
        XCTAssertEqual(translated?.steps[0].selector, "#content")
        XCTAssertEqual(translated?.steps[1].selector, "> *")
    }

    func testHtmlExtractorWithLegadoDefaultSyntax() throws {
        let html = """
        <html><body>
          <div id="chapterlist">
            <dd><a href="/c/1">Chapter 1</a></dd>
            <dd><a href="/c/2">Chapter 2</a></dd>
          </div>
        </body></html>
        """
        let doc = try SwiftSoup.parse(html)
        let extractor = HtmlRuleExtractor()
        let value = try extractor.value(
            from: doc,
            rule: "id.chapterlist@tag.dd@tag.a.0@href",
            baseUrl: URL(string: "https://example.com")!
        )
        XCTAssertEqual(value, "https://example.com/c/1")
    }

    func testHtmlExtractorWithTextNodes() throws {
        let html = """
        <html><body>
          <div id="content">
            Paragraph 1<br/>Paragraph 2<br/>Paragraph 3
          </div>
        </body></html>
        """
        let doc = try SwiftSoup.parse(html)
        let extractor = HtmlRuleExtractor()
        let value = try extractor.value(
            from: doc,
            rule: "id.content@textNodes",
            baseUrl: URL(string: "https://example.com")!
        )
        XCTAssertTrue(value.contains("Paragraph 1"))
        XCTAssertTrue(value.contains("Paragraph 2"))
    }

    func testRelaxedJSONDirectiveParsing() {
        let text = "/search.php,{method: 'POST', body: 'searchkey={{key}}', charset: 'gbk'}"
        let parser = SourceURLDirectiveParser()
        let directive = parser.parse(text)
        XCTAssertEqual(directive.urlText, "/search.php")
        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(directive.expectedCharset, "gbk")
    }

    func testResponseTextDecoderGBK() {
        let decoder = ResponseTextDecoder()
        // "斗破苍穹" in GB18030 / GBK hex: B6 B7 C6 C6 B2 D4 C7 ED
        let gbkBytes: [UInt8] = [0xB6, 0xB7, 0xC6, 0xC6, 0xB2, 0xD4, 0xF1, 0xB7]
        let data = Data(gbkBytes)
        let decoded = decoder.decode(data: data, headers: [:], preferredCharset: "gbk")
        XCTAssertEqual(decoded, "斗破苍穹")
    }
}
