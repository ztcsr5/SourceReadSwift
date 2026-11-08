import XCTest
@testable import SourceReadSwift

final class Release117PurificationTests: XCTestCase {
    func testWatermarkPresetPreservesProseStartingWithASiteName() throws {
        let preset = try XCTUnwrap(PurifyRulePreset.builtIn.first { $0.id == "anti-scraping" })
        let original = "飘天文学是他口中提到的网站。\n最新网址写在纸上，他却没有打开。\n正常故事继续。"
        XCTAssertEqual(PurifyRuleEvaluator.apply(rules: preset.patterns, to: original), original)
        let advertisement = "正文\n飘天文学网首发：https://example.invalid\n最新网址：https://example.invalid\n结尾"
        XCTAssertEqual(PurifyRuleEvaluator.apply(rules: preset.patterns, to: advertisement), "正文\n结尾")
    }

    private let added = Set(["navigation-lines", "page-markers", "site-link-prompts", "control-residue"])
    private var rules: [String] { PurifyRulePreset.builtIn.filter { added.contains($0.id) }.flatMap(\.patterns) }

    func testEveryPresetHasUniqueIDAndCompilableBoundedRegex() throws {
        XCTAssertEqual(Set(PurifyRulePreset.builtIn.map(\.id)).count, PurifyRulePreset.builtIn.count)
        XCTAssertEqual(rules.count, 6)
        for rule in PurifyRulePreset.builtIn.flatMap(\.patterns) {
            let pattern = rule.components(separatedBy: "##")[0]
            _ = try NSRegularExpression(pattern: pattern)
        }
    }

    func testRemovesWholeNavigationAndPageMarkerLinesButKeepsParagraphSeparation() {
        let text = "正文甲\r\n上一章\r\n下一页\r\n（第 1 / 3 页）\r\n正文乙\r\n下一章"
        XCTAssertEqual(PurifyRuleEvaluator.apply(rules: rules, to: text), "正文甲\r\n正文乙\r\n")
    }

    func testPreservesQuotedDialogueShortProseURLsAndNormalPunctuation() {
        let text = "“下一章。”\n他说，上一页还有名字。\n下一章 他回家了\n第1/3页上写着她的名字。\n正文网址 https://example.invalid/path\n手机用户请访问图书馆。\n“手机用户请访问：https://example.invalid”\n『色』、\"引号\"、繁體字都不应改写。\n\t正常换行\n"
        XCTAssertEqual(PurifyRuleEvaluator.apply(rules: rules, to: text), text)
    }

    func testRemovesOnlyExplicitStandaloneSiteLinkPromptsAndEmptyHTMLResidue() {
        let text = "正文\n手机用户请访问：https://example.invalid/book\n&nbsp;<br />\n这是&nbsp;原文\n末\u{0001}段\n"
        XCTAssertEqual(PurifyRuleEvaluator.apply(rules: rules, to: text), "正文\n这是&nbsp;原文\n末段\n")
    }

    @MainActor func testPresetsAreNotAutomaticallyEnabledAndImportIsReversible() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PurifyRuleStore(persistence: PurifyRulePersistence(rootURL: root))
        XCTAssertTrue(store.rules.isEmpty)
        let original = "上一章\n真实正文"
        XCTAssertEqual(store.preview(text: original), original)
        XCTAssertEqual(store.importPatterns(rules), 6)
        XCTAssertEqual(store.importPatterns(rules), 0)
        XCTAssertEqual(store.preview(text: original), "真实正文")
        store.setAllEnabled(false)
        XCTAssertEqual(store.preview(text: original), original)
        XCTAssertTrue(store.restore([])); XCTAssertTrue(store.rules.isEmpty)
    }
}
