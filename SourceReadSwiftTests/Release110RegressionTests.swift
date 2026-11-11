import XCTest
import UIKit
import WebKit
import JavaScriptCore
@testable import SourceReadSwift

final class Release110RegressionTests: XCTestCase {
    func testNewExplicitJumpCancelsOldSmoothMotionAndFallback() throws {
        let shell = WebReaderHTML.shell
        // Swift multiline literals strip their closing delimiter's indent.
        // Locate function names, not source-file indentation.
        let motionStart = try XCTUnwrap(shell.range(of: "function stopScrollAnimation()")).lowerBound
        let motionEnd = try XCTUnwrap(shell.range(of: "function pageStep(", range: motionStart..<shell.endIndex)).lowerBound
        let jumpStart = try XCTUnwrap(shell.range(of: "function scrollToFlat(")).lowerBound
        let jumpEnd = try XCTUnwrap(shell.range(of: "/// 回到文档顶端", range: jumpStart..<shell.endIndex)).lowerBound
        let context = try XCTUnwrap(JSContext())
        var exception: String?
        context.exceptionHandler = { _, value in exception = value?.toString() }
        context.evaluateScript("""
        var scrollAnimationGeneration = 0, timers = [], messages = [], nextTarget = 200;
        var performance = {now: function() { return 123; }};
        var state = {revision: 'r', visible: 0};
        var content = {querySelector: function() { return {getBoundingClientRect: function() { return {top: nextTarget - window.scrollY}; }}; }};
        var window = {scrollY: 0, nativeTarget: null,
          scrollTo: function(x, y) { if (typeof x === 'object') { this.nativeTarget = x.top; } else { this.nativeTarget = null; this.scrollY = y; } },
          setTimeout: function(cb) { timers.push(cb); }, requestAnimationFrame: function() {}};
        function topInset() { return 0; }
        function onScroll() {}
        function post(m) { messages.push(m); }
        // This isolated cancellation test has no DOM; real position geometry is
        // exercised by ReaderScrollCadenceTests with the complete WebKit shell.
        function reportVisiblePosition(now) { post({type: 'visible', requestKey: state.activeScrollKey, at: now}); }
        """)
        context.evaluateScript(String(shell[motionStart..<motionEnd]) + String(shell[jumpStart..<jumpEnd]))
        context.evaluateScript("""
        scrollToFlat(1, true, 'old-speech', 'r');
        nextTarget = 0;
        scrollToFlat(0, false, 'new-toc', 'r');
        timers.forEach(function(cb) { cb(); });
        if (window.nativeTarget !== null) { window.scrollY = window.nativeTarget; }
        """)
        XCTAssertNil(exception)
        XCTAssertEqual(context.evaluateScript("window.scrollY")?.toInt32(), 0)
        XCTAssertEqual(context.evaluateScript("messages.filter(function(m) { return m.type === 'scroll-applied' && m.requestKey === 'old-speech'; }).length")?.toInt32(), 0)
        XCTAssertEqual(context.evaluateScript("messages.filter(function(m) { return m.type === 'scroll-applied' && m.requestKey === 'new-toc'; }).length")?.toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("messages.filter(function(m) { return m.type === 'visible'; }).length")?.toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("messages[messages.length - 1].requestKey")?.toString(), "new-toc")
    }

    /// Real WebKit swallows an opening placement while a fresh document is
    /// still laying out, and a later style/image pass can undo one that did
    /// land. Either way the saved paragraph used to be acknowledged anyway.
    func testOpeningPlacementSurvivesSwallowedScrollAndLateLayoutDrift() throws {
        let shell = WebReaderHTML.shell
        let motionStart = try XCTUnwrap(shell.range(of: "function stopScrollAnimation()")).lowerBound
        let motionEnd = try XCTUnwrap(shell.range(of: "function pageStep(", range: motionStart..<shell.endIndex)).lowerBound
        let jumpStart = try XCTUnwrap(shell.range(of: "function scrollToFlat(")).lowerBound
        let jumpEnd = try XCTUnwrap(shell.range(of: "/// 回到文档顶端", range: jumpStart..<shell.endIndex)).lowerBound
        let body = String(shell[motionStart..<motionEnd]) + String(shell[jumpStart..<jumpEnd])

        func outcome(dropFirstScroll: Bool, driftAtFrame: Int?, targetTop: Double, viewport: Double) throws -> (Int, Int, Int) {
            let context = try XCTUnwrap(JSContext())
            var exception: String?
            context.exceptionHandler = { _, value in exception = value?.toString() }
            context.evaluateScript("""
            var scrollAnimationGeneration = 0, frames = [], messages = [], frameIndex = 0;
            var targetTop = \(targetTop), drift = \(driftAtFrame.map(String.init) ?? "-1"), drops = \(dropFirstScroll ? 1 : 0);
            var performance = {now: function() { return 123; }};
            var state = {revision: 'r', visible: -1, activeScrollKey: null};
            var content = {querySelector: function() { return {getBoundingClientRect: function() {
              return {top: targetTop - window.scrollY, bottom: targetTop - window.scrollY + 80}; }}; }};
            var window = {scrollY: 0, innerHeight: \(viewport),
              scrollTo: function(x, y) {
                if (typeof x === 'object') { return; }
                if (y > 0 && drops > 0) { drops -= 1; return; }
                this.scrollY = y;
              },
              setTimeout: function(cb) { frames.push(cb); },
              requestAnimationFrame: function(cb) { frames.push(cb); }};
            function topInset() { return 0; }
            function onScroll() {}
            function post(m) { messages.push(m); }
            function reportVisiblePosition() {}
            """)
            context.evaluateScript(body)
            context.evaluateScript("scrollToFlat(30, false, 'opening', 'r', 0, true);")
            context.evaluateScript("""
            for (var round = 0; round < 400 && frames.length; round += 1) {
              frames.shift()();
              frameIndex += 1;
              if (frameIndex === drift) { window.scrollY = 0; }
            }
            """)
            XCTAssertNil(exception)
            let applied = context.evaluateScript("messages.filter(function(m){return m.type==='scroll-applied';}).length")?.toInt32() ?? -1
            let missed = context.evaluateScript("messages.filter(function(m){return m.type==='scroll-miss';}).length")?.toInt32() ?? -1
            let y = context.evaluateScript("window.scrollY")?.toInt32() ?? -1
            return (Int(y), Int(applied), Int(missed))
        }

        let swallowed = try outcome(dropFirstScroll: true, driftAtFrame: nil, targetTop: 3200, viewport: 852)
        XCTAssertEqual(swallowed.0, 3200, "A swallowed first placement must be re-issued until the paragraph is visible")
        XCTAssertEqual(swallowed.1, 1)

        let drifted = try outcome(dropFirstScroll: true, driftAtFrame: 6, targetTop: 3200, viewport: 852)
        XCTAssertEqual(drifted.0, 3200, "A late layout pass must not leave the opening on the wrong line")
        XCTAssertEqual(drifted.1, 1)

        let unreachable = try outcome(dropFirstScroll: false, driftAtFrame: nil, targetTop: 5000, viewport: 100)
        XCTAssertEqual(unreachable.1, 0, "An unreachable target must never be acknowledged as positioned")
        XCTAssertEqual(unreachable.2, 1, "An unreachable target reports a real miss instead of silence")
    }

    func testWebSectionRevisionSeesMiddleParagraphChanges() {
        let old = WebReaderSection(chapterIndex: 1, title: "章", paragraphs: ["首", "旧", "尾"])
        let new = WebReaderSection(chapterIndex: 1, title: "章", paragraphs: ["首", "新", "尾"])
        XCTAssertNotEqual(old.contentSignature, new.contentSignature)
        XCTAssertEqual(old.key, new.key)
    }

    func testBackgroundPayloadKeepsRevisionAndEveryParagraph() throws {
        let section = WebReaderSection(chapterIndex: 29, title: "第二十九章", paragraphs: ["甲", "乙", "丙"])
        let text = try XCTUnwrap(WebReaderContentPayloadBuilder.json(sections: [section],
            showChapterEndBadge: false, traditionalChineseEnabled: false, revision: "generation-29"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(body["revision"] as? String, "generation-29")
        XCTAssertEqual(body["total"] as? Int, 3)
        let encoded = try XCTUnwrap(body["sections"] as? [[String: Any]])
        XCTAssertEqual((encoded[0]["paragraphs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }, ["甲", "乙", "丙"])
    }

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

    func testContinuationRestoresIndentAfterEmbeddedNewline() {
        let rendered = ReaderPageTextBuilder.make(title: nil,
            paragraphs: [.init(text: "续行\n新段落", isContinuation: true, isHighlighted: false)],
            style: ReaderPageTextBuilder.layoutStyle(makeTypography()))
        let first = rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
        let next = rendered.attribute(.paragraphStyle, at: 3, effectiveRange: nil) as! NSParagraphStyle
        XCTAssertEqual(first.firstLineHeadIndent, 0)
        XCTAssertEqual(next.firstLineHeadIndent, 40)
        XCTAssertEqual(rendered.string, "续行\n新段落")
    }

    func testAdvertisementRulesMatchOnlyTargetedDomains() throws {
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(WebAdvertisementRules.json.utf8)) as? [[String: Any]])
        let regexes = try rules.filter { ($0["action"] as? [String: Any])?["type"] as? String == "block" }.map { rule in
            let trigger = try XCTUnwrap(rule["trigger"] as? [String: Any])
            return try NSRegularExpression(pattern: XCTUnwrap(trigger["url-filter"] as? String))
        }
        XCTAssertEqual(regexes.count, 3)
        for url in ["https://doubleclick.net/ad.js", "https://ads.doubleclick.net/ad.js", "https://googlesyndication.com/pagead.js"] {
            XCTAssertTrue(regexes.contains { $0.firstMatch(in: url, range: NSRange(location: 0, length: url.utf16.count)) != nil })
        }
        for url in ["https://example.com/chapter.html", "https://notdoubleclick.net/chapter.html", "https://doubleclick.net.example.com/chapter.html"] {
            XCTAssertFalse(regexes.contains { $0.firstMatch(in: url, range: NSRange(location: 0, length: url.utf16.count)) != nil })
        }
    }

    @MainActor func testSameURLNavigationInvalidatesExtractionEpoch() {
        let session = WebReadingSession()
        let before = session.documentGeneration
        session.article = SmartWebArticle(title: "旧页", paragraphs: ["旧正文"])
        session.isExtracting = true
        session.documentDidStartLoading()
        XCTAssertGreaterThan(session.documentGeneration, before)
        XCTAssertNil(session.article)
        XCTAssertFalse(session.isExtracting)
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
