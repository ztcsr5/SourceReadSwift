import XCTest
@testable import SourceReadSwift

/// Field rules that never run a selector.
///
/// Captured from the rows-corpus failures: a source can put the whole
/// extraction into `##pattern##replacement###`, where the selector part is
/// empty and Legado feeds the element's outer HTML straight to the regex.
/// Two live examples:
///   * 518 随心看吧  `##="newWebView\('([^']+)'##$1###`
///   * 975 未来天王 `##<a\s*href="([^"]+)"##$1###`
/// The old code sent `##...` to the CSS selector path, so book URLs came back
/// empty even though the row was selected.
final class HtmlRuleLegacyRegexTests: XCTestCase {
    private let base = URL(string: "https://example.com/")!

    func testRegexOnlyRuleReadsOnclickHandler() throws {
        let html = #"""
        <ul><li class="v-list-item"><a href="javascript:;" onclick="newWebView('https://m.example.com/book/42')">斗破苍穹</a></li></ul>
        """#
        let extractor = HtmlRuleExtractor()
        let rows = try extractor.select(html, baseUrl: base, listRule: "class.v-list-item")
        XCTAssertEqual(rows.count, 1)
        let url = try extractor.value(
            from: rows[0],
            rule: #"##="newWebView\('([^']+)'##$1###"#,
            fallback: nil,
            baseUrl: base
        )
        XCTAssertEqual(url, "https://m.example.com/book/42")
    }

    func testRegexOnlyRuleReadsAnchorHrefFromOuterHTML() throws {
        let html = #"""
        <ul><li class="s2"><a href="/book/975.html">未来天王</a></li></ul>
        """#
        let extractor = HtmlRuleExtractor()
        let rows = try extractor.select(html, baseUrl: base, listRule: ".s2")
        XCTAssertEqual(rows.count, 1)
        let href = try extractor.value(
            from: rows[0],
            rule: "##<a\\s*href=\"([^\"]+)\"##$1###",
            fallback: nil,
            baseUrl: base
        )
        XCTAssertEqual(href, "/book/975.html")
    }

    func testRelativeXPathFieldRuleKeepsStepPosition() throws {
        // novelslist2 rows: the book name lives in the second <span>, so the
        // field rule is `/span[2]/a/text()`. Translating `[2]` to the legacy
        // trailing `@1` produced `span@1 a`, which selected nothing.
        let html = #"""
        <div class="novelslist2"><ul>
          <li><span class="s1">1</span><span class="s2"><a href="/book/1">斗破苍穹</a></span><span class="s3"><a>天蚕土豆</a></span></li>
        </ul></div>
        """#
        let extractor = HtmlRuleExtractor()
        let rows = try extractor.select(html, baseUrl: base, listRule: "class.novelslist2@ul@li")
        XCTAssertEqual(rows.count, 1)
        let name = try extractor.value(from: rows[0], rule: "/span[2]/a/text()", fallback: nil, baseUrl: base)
        XCTAssertEqual(name, "斗破苍穹")
        let href = try extractor.value(from: rows[0], rule: "/span[2]/a/@href", fallback: nil, baseUrl: base)
        XCTAssertEqual(href, "https://example.com/book/1")
        let author = try extractor.value(from: rows[0], rule: "/span[3]/a/text()", fallback: nil, baseUrl: base)
        XCTAssertEqual(author, "天蚕土豆")
    }

    func testExplicitCSSRuleKeepsTrailingAttribute() throws {
        // 746 红牛资源: `@css:.xing_vb4>a@textNodes`. The `@` chain translator
        // must not split the compound selector at its `>`.
        let html = #"""
        <div class="xing_vb"><ul><li><span class="xing_vb4"><a href="/1">第一章</a></span></li></ul></div>
        """#
        let extractor = HtmlRuleExtractor()
        let rows = try extractor.select(html, baseUrl: base, listRule: "@css:.xing_vb>ul")
        XCTAssertEqual(rows.count, 1)
        let text = try extractor.value(
            from: rows[0],
            rule: "@css:.xing_vb4>a@textNodes",
            fallback: nil,
            baseUrl: base
        )
        XCTAssertEqual(text, "第一章")
    }
}
