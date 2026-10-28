import XCTest
import SwiftSoup
@testable import SourceReadSwift

/// `@html` and `@all` follow Legado's `AnalyzeByJSoup` contract: both return
/// outer HTML, and `html` additionally drops `<script>` / `<style>` blocks so
/// inline JavaScript never reaches chapter text.
final class HtmlAttributeSemanticsTests: XCTestCase {
    func testHtmlAttributeUsesOuterHTMLAndDropsScripts() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div id="content"><script>alert(1)</script><style>.a{color:red}</style><p>正文</p></div>
        </body></html>
        """)

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: "#content@html",
            baseUrl: URL(string: "https://example.com")!
        )

        XCTAssertTrue(value.hasPrefix("<div"), "outer HTML keeps the container node: \(value)")
        XCTAssertTrue(value.contains("<p>正文</p>"))
        XCTAssertFalse(value.lowercased().contains("<script"))
        XCTAssertFalse(value.lowercased().contains("<style"))
    }

    func testAllAttributeUsesOuterHTML() throws {
        let document = try SwiftSoup.parse("<html><body><p>A</p><p>B</p></body></html>")

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: "p@all",
            baseUrl: URL(string: "https://example.com")!
        )

        XCTAssertEqual(value, "<p>A</p><p>B</p>")
    }

    func testHtmlAttributeKeepsInnerMarkup() throws {
        let document = try SwiftSoup.parse("<html><body><div class=\"content\"><p>一</p><p>二</p></div></body></html>")

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: ".content@html",
            baseUrl: URL(string: "https://example.com")!
        )

        XCTAssertTrue(value.hasPrefix("<div class=\"content\">"))
        XCTAssertTrue(value.hasSuffix("</div>"))
        XCTAssertTrue(value.contains("<p>一</p>"))
    }
}
