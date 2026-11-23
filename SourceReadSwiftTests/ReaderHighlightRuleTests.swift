import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

final class ReaderHighlightRuleTests: XCTestCase {
    func testWebDocumentGetsICULookbehindMatchesAsUTF16RatherThanJavaScriptPatterns() throws {
        let rule = ReaderHighlightRule(id: "colour", name: "引文", pattern: "(?<=「)正文(?=」)", isRegex: true)
        let sections = [WebReaderSection(chapterIndex: 0, title: "章名", paragraphs: ["🚀「正文」"])]
        let snapshot = WebReaderContentPayloadBuilder.Snapshot(sections: sections, showChapterEndBadge: false,
            traditionalChineseEnabled: false, revision: "on", highlightRules: [rule])
        let json = try XCTUnwrap(WebReaderContentPayloadBuilder.json(sections: sections, snapshot: snapshot))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let section = try XCTUnwrap((body["sections"] as? [[String: Any]])?.first)
        let prose = try XCTUnwrap((section["paragraphs"] as? [[String: Any]])?.first)
        let mark = try XCTUnwrap((prose["marks"] as? [[Any]])?.first)
        XCTAssertEqual(mark[0] as? String, rule.id)
        XCTAssertEqual(mark[1] as? Int, 3); XCTAssertEqual(mark[2] as? Int, 5)
        XCTAssertFalse(json.contains(rule.pattern))
        let noRules = WebReaderContentPayloadBuilder.Snapshot(sections: sections, showChapterEndBadge: false,
            traditionalChineseEnabled: false, revision: "off")
        let off = try XCTUnwrap(WebReaderContentPayloadBuilder.json(sections: sections, snapshot: noRules, reusing: snapshot))
        XCTAssertFalse(off.contains("\"reuse\":true")); XCTAssertFalse(off.contains("\"marks\""))
    }

    func testBuiltInTemplatesAreDisabledByDefaultAndHaveNonEmptyPatterns() {
        let templates = ReaderHighlightRule.builtInTemplates
        XCTAssertGreaterThanOrEqual(templates.count, 2)
        for rule in templates {
            XCTAssertFalse(rule.enabled, "Built-in templates must opt in cleanly rather than hijacking reading pages by default")
            XCTAssertFalse(rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertNil(ReaderHighlightMatcher.validationError(pattern: rule.pattern, isRegex: rule.isRegex))
        }
    }

    func testValidationRejectsEmptyAndMalformedRegex() {
        XCTAssertEqual(ReaderHighlightMatcher.validationError(pattern: "   ", isRegex: false), .emptyPattern)
        XCTAssertEqual(ReaderHighlightMatcher.validationError(pattern: "", isRegex: true), .emptyPattern)

        if case .invalidRegex = ReaderHighlightMatcher.validationError(pattern: "[unclosed", isRegex: true) {
            // expected
        } else {
            XCTFail("Malformed regex should return .invalidRegex")
        }

        XCTAssertNil(ReaderHighlightMatcher.validationError(pattern: "[unclosed", isRegex: false))
        XCTAssertNil(ReaderHighlightMatcher.validationError(pattern: "(?i)SourceRead", isRegex: true))
    }

    func testLiteralAndRegexMatchingRespectsCaseAndPCREInlineFlags() {
        let literalInsensitive = ReaderHighlightRule(
            name: "品牌",
            pattern: "sourceread",
            isRegex: false,
            caseSensitive: false,
            preset: .sky
        )
        let literalSensitive = ReaderHighlightRule(
            name: "品牌严格",
            pattern: "SourceRead",
            isRegex: false,
            caseSensitive: true,
            preset: .amber
        )
        let regexPCRE = ReaderHighlightRule(
            name: "系统",
            pattern: "(?i)\\[status:[a-z]+\\]",
            isRegex: true,
            caseSensitive: true,
            preset: .jade
        )

        let text = "欢迎来到 SourceRead 与 sourceread，状态 [STATUS:READY]。"
        let spansInsensitive = ReaderHighlightMatcher.matchedSpans(in: text, rules: [literalInsensitive], isNight: false)
        XCTAssertEqual(spansInsensitive.count, 2)

        let spansSensitive = ReaderHighlightMatcher.matchedSpans(in: text, rules: [literalSensitive], isNight: false)
        XCTAssertEqual(spansSensitive.count, 1)

        let regexSpans = ReaderHighlightMatcher.matchedSpans(in: text, rules: [regexPCRE], isNight: false)
        XCTAssertEqual(regexSpans.count, 1)
        XCTAssertEqual((text as NSString).substring(with: regexSpans[0].range), "[STATUS:READY]")
    }

    func testOverlappingSpansResolveNonOverlappingLeftToRightByPriority() {
        let higherPriority = ReaderHighlightRule(
            id: "r1",
            name: "主角名",
            pattern: "顾清寒",
            isRegex: false,
            preset: .amber
        )
        let widerLowerPriority = ReaderHighlightRule(
            id: "r2",
            name: "短语",
            pattern: "清寒收剑",
            isRegex: false,
            preset: .lavender
        )

        let text = "顾清寒收剑入鞘"
        let spans = ReaderHighlightMatcher.matchedSpans(
            in: text,
            rules: [higherPriority, widerLowerPriority],
            isNight: false
        )
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].ruleID, "r1")
        XCTAssertEqual((text as NSString).substring(with: spans[0].range), "顾清寒")
    }

    func testScopeFilteringMatchesBookTitleAndSourceURLCaseInsensitively() {
        let globalRule = ReaderHighlightRule(id: "all", name: "全局", pattern: "夜雨", scopeKind: .all)
        let bookRule = ReaderHighlightRule(id: "book", name: "仅此书", pattern: "夜雨", scopeKind: .bookTitle, scopeKeyword: "将夜")
        let sourceRule = ReaderHighlightRule(id: "src", name: "仅此源", pattern: "夜雨", scopeKind: .sourceURL, scopeKeyword: "example.org")

        let matched = ReaderHighlightMatcher.activeRules(
            from: [globalRule, bookRule, sourceRule],
            bookTitle: "雪夜将夜行",
            sourceURL: "https://sub.EXAMPLE.ORG/book/1"
        )
        XCTAssertEqual(matched.map(\.id), ["all", "book", "src"])

        let unmatched = ReaderHighlightMatcher.activeRules(
            from: [globalRule, bookRule, sourceRule],
            bookTitle: "另一本书",
            sourceURL: "https://other.net/book/1"
        )
        XCTAssertEqual(unmatched.map(\.id), ["all"])
    }

    func testUIKitAndSwiftUIAttributedHighlightsSetPillWithoutAnyUnderline() {
        let rule = ReaderHighlightRule(
            id: "pill",
            name: "宝剑",
            pattern: "青霜剑",
            isRegex: false,
            enabled: true,
            preset: .lavender,
            tintForeground: true,
            isBold: true
        )
        let text = "腰间青霜剑微鸣。"
        let baseFont = UIFont.systemFont(ofSize: 18, weight: .regular)
        let boldFont = UIFont.systemFont(ofSize: 18, weight: .semibold)
        let baseInk = UIColor.darkText
        let paragraph = NSMutableParagraphStyle()

        let uiAttr = ReaderHighlightMatcher.uiKitAttributedString(
            for: text,
            rules: [rule],
            baseFont: baseFont,
            boldFont: boldFont,
            baseInk: baseInk,
            paragraphStyle: paragraph,
            letterSpacing: 0.5,
            isNight: false
        )

        let fullNSRange = NSRange(location: 0, length: (text as NSString).length)
        uiAttr.enumerateAttributes(in: fullNSRange) { attrs, _, _ in
            XCTAssertNil(attrs[.underlineStyle], "Highlights must never apply underlineStyle")
            XCTAssertNil(attrs[.underlineColor], "Highlights must never apply underlineColor")
        }
        let targetNSRange = (text as NSString).range(of: "青霜剑")
        XCTAssertNotNil(uiAttr.attribute(.backgroundColor, at: targetNSRange.location, effectiveRange: nil))
        let fontAtMatch = uiAttr.attribute(.font, at: targetNSRange.location, effectiveRange: nil) as? UIFont
        XCTAssertEqual(fontAtMatch, boldFont)

        var swiftAttr = AttributedString(text)
        ReaderHighlightMatcher.applyHighlights(
            to: &swiftAttr,
            sourceText: text,
            rules: [rule],
            boldFont: .system(size: 18, weight: .semibold),
            isNight: false
        )
        for run in swiftAttr.runs {
            XCTAssertNil(run.swiftUI.underlineStyle)
            XCTAssertNil(run.uiKit.underlineStyle)
        }
        let pillRuns = swiftAttr.runs.filter { $0.swiftUI.backgroundColor != nil }
        XCTAssertEqual(pillRuns.count, 1)
    }

    @MainActor
    func testStorePersistsUpdatesTogglesRemovalsAndRestoresBuiltIns() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("highlight_rules.json")
        let store = ReaderHighlightRuleStore(fileURL: fileURL, initialTemplates: [])

        let custom = ReaderHighlightRule(
            id: "custom-1",
            name: "核心词",
            pattern: "飞剑",
            enabled: true,
            preset: .rose
        )
        XCTAssertTrue(store.addOrUpdate(custom))
        XCTAssertEqual(store.rules.map(\.id), ["custom-1"])

        store.setEnabled(false, ruleID: "custom-1")
        XCTAssertEqual(store.rules.first?.enabled, false)

        let invalid = ReaderHighlightRule(id: "bad", name: "错误正则", pattern: "[abc", isRegex: true)
        XCTAssertFalse(store.addOrUpdate(invalid))
        XCTAssertNotNil(store.lastError)

        let reloaded = ReaderHighlightRuleStore(fileURL: fileURL, initialTemplates: [])
        XCTAssertEqual(reloaded.rules.map(\.id), ["custom-1"])
        XCTAssertEqual(reloaded.rules.first?.enabled, false)

        reloaded.restoreDefaultTemplates()
        XCTAssertTrue(reloaded.rules.contains(where: { $0.id == "builtin.dialogue" }))

        reloaded.remove(ruleID: "custom-1")
        XCTAssertFalse(reloaded.rules.contains(where: { $0.id == "custom-1" }))
    }
}
