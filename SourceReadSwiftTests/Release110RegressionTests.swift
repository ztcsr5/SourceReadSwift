import XCTest
import UIKit
import WebKit
@testable import SourceReadSwift

final class Release110RegressionTests: XCTestCase {
    func testOldDOMCannotReportProgressThroughNewChapterWindow() {
        XCTAssertFalse(ReaderWebMessagePolicy.matchesRevision("old", expected: "new"))
        XCTAssertFalse(ReaderWebMessagePolicy.matchesRevision(nil, expected: "new"))
        XCTAssertFalse(ReaderWebMessagePolicy.matchesRevision("", expected: ""))
        XCTAssertTrue(ReaderWebMessagePolicy.matchesRevision("new", expected: "new"))
    }

    func testLateChapterJumpAcknowledgementCannotClearNewJump() {
        XCTAssertFalse(ReaderWebMessagePolicy.matchesRequest("jump29", pending: "jump30"))
        XCTAssertFalse(ReaderWebMessagePolicy.matchesRequest(nil, pending: "jump30"))
        XCTAssertFalse(ReaderWebMessagePolicy.matchesRequest("jump30", pending: nil))
        XCTAssertTrue(ReaderWebMessagePolicy.matchesRequest("jump30", pending: "jump30"))
    }

    func testClosingQuotesKeepTheirNaturalAdvance() {
        let typography = makeTypography()
        let text = "“请不要在我家里抽烟。”汪淼说，‘好。’他回答。"
        let rendered = ReaderPageTextBuilder.make(title: nil,
            paragraphs: [.init(text: text, isContinuation: false, isHighlighted: false)],
            style: ReaderPageTextBuilder.layoutStyle(typography))
        for quote in ["”", "’"] {
            let location = (text as NSString).range(of: quote).location
            let kern = rendered.attribute(.kern, at: location, effectiveRange: nil) as? CGFloat
            XCTAssertEqual(kern ?? -999, typography.letterSpacing, accuracy: 0.001)
        }
    }

    func testIndentIsGeometricAndDoesNotChangeSourceOrContinuation() {
        let typography = makeTypography()
        let rendered = ReaderPageTextBuilder.make(title: nil, paragraphs: [
            .init(text: "第一段正文", isContinuation: false, isHighlighted: false),
            .init(text: "续页正文", isContinuation: true, isHighlighted: false)
        ], style: ReaderPageTextBuilder.layoutStyle(typography))
        XCTAssertEqual(rendered.string, "第一段正文\n续页正文")
        let first = rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
        let next = rendered.attribute(.paragraphStyle, at: 6, effectiveRange: nil) as! NSParagraphStyle
        XCTAssertEqual(first.firstLineHeadIndent, 40)
        XCTAssertEqual(first.alignment, .justified)
        XCTAssertEqual(next.firstLineHeadIndent, 0)
    }

    func testHeaderModeAlsoIncludesLargeChapterOpeningTitle() {
        let typography = makeTypography()
        for chrome in [ReaderPageChromeLayout.header, .inline, .hidden] {
            let context = ReaderChapterPaginationContext(typography: typography, titleTypography: typography,
                chromeLayout: chrome, imageStyle: .standard, viewportHeight: 568,
                pagePadding: 21, footerHeight: 14, traditionalChinese: false)
            let text = String(repeating: "正文内容，不能丢字。", count: 60)
            let pages = ReaderChapterPaginator.paginate(chapterIndex: 3, title: "第二十九章", paragraphs: [text], context: context)
            XCTAssertEqual(pages.first?.includesTitle, chrome != .hidden)
            XCTAssertEqual(pages.flatMap(\.paragraphs).map(\.text).joined(), text)
        }
    }

    func testExtractionPreservesBRShortLinesAndRepeatedDialogue() {
        let article = SmartWebArticleExtractor.extract(html: "<article>“好。”<br>“好。”<br>嗯<p>末段。</p></article>")
        XCTAssertEqual(article.paragraphs, ["“好。”", "“好。”", "嗯", "末段。"])
    }

    func testExtractionChoosesArticleInsteadOfNavigationLikeContentBox() {
        let article = SmartWebArticleExtractor.extract(html: "<div class='content'><a href='/'>目录登录首页</a></div><article><p>这里才是真正的正文内容。</p></article>")
        XCTAssertEqual(article.paragraphs, ["这里才是真正的正文内容。"])
    }

    func testBuiltInPurificationDoesNotDeleteNormalQuotedContent() {
        let text = "他说：『色』是一个字。\n“请不要在我家里抽烟。”\nla 是原文，不要随意删除。"
        let rules = PurifyRulePreset.builtIn.flatMap(\.patterns)
        XCTAssertEqual(PurifyRuleEvaluator.apply(rules: rules, to: text), text)
    }

    func testBuiltInPurificationRemovesWholePromptLinesOnly() {
        let text = "正文\n最新网址：https://example.invalid\n他说最新网址并没有变化。\n请下载本站APP阅读\n结尾"
        let result = PurifyRuleEvaluator.apply(rules: PurifyRulePreset.builtIn.flatMap(\.patterns), to: text)
        XCTAssertTrue(result.contains("他说最新网址并没有变化。"))
        XCTAssertFalse(result.contains("https://example.invalid"))
        XCTAssertFalse(result.contains("请下载本站APP"))
        XCTAssertTrue(result.contains("结尾"))
    }

    func testInvalidPurificationRegexPreservesSource() {
        XCTAssertEqual(PurifyRuleEvaluator.apply(rule: "[##", to: "完整正文"), "完整正文")
    }

    @MainActor func testAdvertisementRuleListCompilesOnNativeWebKit() {
        let done = expectation(description: "WebKit compiles conservative content blocker")
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "release110-test", encodedContentRuleList: WebAdvertisementRules.json) { list, error in
            XCTAssertNil(error)
            XCTAssertNotNil(list)
            done.fulfill()
        }
        wait(for: [done], timeout: 15)
    }

    private func makeTypography() -> ReaderPageTypography {
        .init(font: .systemFont(ofSize: 20), titleFont: .boldSystemFont(ofSize: 26),
              lineSpacing: 8, letterSpacing: 0.3, paragraphSpacing: 16,
              firstLineIndent: 40, titleSpacing: 12, contentWidth: 280, contentHeight: 320)
    }
}
