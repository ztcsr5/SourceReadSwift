import XCTest
import SwiftSoup
@testable import SourceReadSwift

/// Batch A / item 2 — the synopsis must come from the whole container when the
/// rule only sampled a slice. Every fixture below mirrors a rule shape that the
/// bundled `shareBookSource11` collection actually ships:
///
/// * `meta[property=og:description]@content` (千白羽 / 话本 / 得奇) — the site
///   truncates the meta description, the page keeps the full block.
/// * `@css:.intro dd@text` (bqg128) — the rule samples one child, not the block.
/// * `.brief@html` (aggregate fixture) — already complete, must stay untouched.
final class SynopsisContainerPreferenceTests: XCTestCase {
    private let fullSynopsis = String(repeating: "少年自小镇走出，一路向北方。", count: 24)

    private func source(introRule: String) -> BookSource {
        BookSource(
            bookSourceName: "SynopsisFixture",
            bookSourceUrl: "https://synopsis.invalid",
            ruleBookInfo: SourceRule(fields: ["name": "h1@text", "intro": introRule])
        )
    }

    private func response(_ body: String) -> SourceResponse {
        SourceResponse(url: URL(string: "https://synopsis.invalid/book/1")!, statusCode: 200,
            headers: [:], body: body, data: Data(body.utf8))
    }

    private func detail(introRule: String, body: String, title: String = "剑来") throws -> BookDetail {
        let book = SearchBook(
            name: title,
            author: nil,
            coverUrl: nil,
            bookUrl: "https://synopsis.invalid/book/1",
            sourceName: "SynopsisFixture",
            sourceUrl: "https://synopsis.invalid"
        )
        return try BookDetailParser()
            .parse(source: source(introRule: introRule), book: book, response: response(body))
            .get()
    }

    func testTruncatedMetaDescriptionIsReplacedByTheWholeContainer() throws {
        let body = """
        <html><head>
          <meta property="og:description" content="少年自小镇走出，一路…">
        </head><body>
          <h1>剑来</h1>
          <div class="book-intro"><p>\(fullSynopsis)</p></div>
        </body></html>
        """
        let parsed = try detail(introRule: "meta[property=og:description]@content", body: body)
        XCTAssertEqual(parsed.intro, fullSynopsis, "The whole block must win over the site's excerpt")
        XCTAssertFalse(parsed.intro?.hasSuffix("…") ?? true)
    }

    func testRuleThatSamplesOneChildIsWidenedToItsContainer() throws {
        // bqg128 ships `@css:.intro dd@text`; the rule reaches one child only.
        let body = """
        <html><body>
          <h1>剑来</h1>
          <dl class="intro">
            <dd>少年自小镇走出，一路…</dd>
            <p>\(fullSynopsis)</p>
          </dl>
        </body></html>
        """
        let parsed = try detail(introRule: "@css:.intro dd@text", body: body)
        let intro = try XCTUnwrap(parsed.intro)
        XCTAssertTrue(intro.hasPrefix("少年自小镇走出，一路…"), "Got: \(intro)")
        XCTAssertTrue(intro.contains(fullSynopsis), "The rest of the block must survive; got: \(intro)")
        XCTAssertGreaterThan(intro.count, "少年自小镇走出，一路…".count)
    }

    func testCompleteRuleValueIsNeverReplacedByASmallerOrDifferentBlock() throws {
        let ruleText = "第一段。" + fullSynopsis
        let body = """
        <html><body>
          <h1>剑来</h1>
          <div class="brief">\(ruleText)</div>
          <div class="intro">另一段完全不同的文字，长度也不短，但它不是这条规则指向的内容。\(fullSynopsis)</div>
        </body></html>
        """
        let parsed = try detail(introRule: ".brief@text", body: body)
        XCTAssertEqual(parsed.intro, ruleText, "A complete rule result must be left alone")
    }

    func testEmptyRuleValueFallsBackToTheContainer() throws {
        let body = """
        <html><body>
          <h1>剑来</h1>
          <span class="empty"></span>
          <div id="jianjie"><p>\(fullSynopsis)</p></div>
        </body></html>
        """
        let parsed = try detail(introRule: ".empty@text", body: body)
        XCTAssertEqual(parsed.intro, fullSynopsis)
    }

    func testHardTruncatedRuleWithoutEllipsisRecoversTheWholeContainer() throws {
        // Sites that cut `meta[description]` at N characters without appending
        // an ellipsis used to slip through: the rule value is a strict prefix
        // of the real block, so it must widen instead of staying a fragment.
        let excerpt = String(fullSynopsis.prefix(40))
        let body = """
        <html><head>
          <meta property="og:description" content="\(excerpt)">
        </head><body>
          <h1>剑来</h1>
          <div class="book-intro"><p>\(fullSynopsis)</p></div>
        </body></html>
        """
        let parsed = try detail(introRule: "meta[property=og:description]@content", body: body)
        XCTAssertEqual(parsed.intro, fullSynopsis)
        XCTAssertFalse(BookDetailParser.looksTruncatedIntro(excerpt))
    }

    func testUnlabelledParagraphIsUsedWhenTheRuleSampledItsPrefix() throws {
        let excerpt = String(fullSynopsis.prefix(40))
        let body = """
        <html><head>
          <meta name="description" content="\(excerpt)">
        </head><body>
          <h1>剑来</h1>
          <p>\(fullSynopsis)</p>
        </body></html>
        """
        let parsed = try detail(introRule: "meta[name=description]@content", body: body)
        XCTAssertEqual(parsed.intro, fullSynopsis,
                       "A page with no intro class/id must still recover its one long prose block")
    }

    func testNavigationBlockAndShortLabelAreNotSynopsis() {
        let navigation = """
        <html><body>
          <ul class="intro-nav">
            <li><a href="/1">第一章</a></li><li><a href="/2">第二章</a></li>
            <li><a href="/3">第三章</a></li><li><a href="/4">第四章</a></li>
          </ul>
          <div class="intro">简介</div>
        </body></html>
        """
        let document = try? SwiftSoup.parse(navigation)
        XCTAssertNil(document.flatMap { BookDetailParser.introContainer(in: $0, bookTitle: "剑来") })
    }

    func testWholePageBodyIsRejectedAsAContainer() {
        let page = "<html><body class=\"intro-page\"><p>\(fullSynopsis)</p></body></html>"
        let document = try? SwiftSoup.parse(page)
        // `body` carries the token, but its text is the page itself.
        XCTAssertNil(document.flatMap { BookDetailParser.introContainer(in: $0, bookTitle: "剑来") })
    }

    func testTruncationDetectionCoversTheExcerptSuffixes() {
        XCTAssertTrue(BookDetailParser.looksTruncatedIntro("一路向北方…"))
        XCTAssertTrue(BookDetailParser.looksTruncatedIntro("一路向北方..."))
        XCTAssertFalse(BookDetailParser.looksTruncatedIntro("一路向北方。"))
        XCTAssertFalse(BookDetailParser.looksTruncatedIntro("   "))
    }
}
