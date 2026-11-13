import XCTest
@testable import SourceReadSwift

final class TxtChapterRuleLibraryTests: XCTestCase {
    private func rule(_ name: String, _ pattern: String, priority: Int, enabled: Bool = true) -> TxtChapterRule {
        TxtChapterRule(name: name, pattern: pattern, isEnabled: enabled, priority: priority)
    }

    func testDisabledLibraryDefersToMode() {
        var divider = LocalTxtSmartDivider()
        divider.ruleLibrary = TxtChapterRuleLibrary(isEnabled: false,
            rules: [rule("永不命中", #"^XYZ$"#, priority: 1000)])
        XCTAssertFalse(divider.isChapterHeading("普通正文段落。"))
        XCTAssertTrue(divider.isChapterHeading("第一章 潜龙勿用"))
    }

    func testEnabledLibraryOverridesBuiltInHeuristics() {
        var divider = LocalTxtSmartDivider()
        divider.ruleLibrary = TxtChapterRuleLibrary(isEnabled: true,
            rules: [rule("仅井号标题", #"^#{1,6}\s+.{1,40}$"#, priority: 10)])
        XCTAssertTrue(divider.isChapterHeading("## 第一幕"))
        XCTAssertFalse(divider.isChapterHeading("第一章 潜龙勿用"),
                       "库启用后，未命中的标题不得退回内置规则，否则关闭规则在界面上毫无效果")
    }

    func testHigherPriorityRuleWinsAndDisabledRuleIsSkipped() {
        let library = TxtChapterRuleLibrary(isEnabled: true, rules: [
            rule("低优先级", #"^第.*章"#, priority: 10),
            rule("高优先级但关闭", #"^第.*章"#, priority: 100, enabled: false),
            rule("中优先级", #"^第.*回"#, priority: 50)
        ])
        XCTAssertEqual(library.orderedEnabledRules.map(\.name), ["中优先级", "低优先级"])
        XCTAssertEqual(library.classify("第一章 潜龙勿用"), true)
        XCTAssertEqual(library.classify("第二回 风起"), true)
        XCTAssertEqual(library.classify("普通正文"), false)
    }

    func testInvalidRegexIsRejectedWithReadableReason() {
        let broken = TxtChapterRule(name: "坏规则", pattern: "^([a-z", priority: 1)
        XCTAssertFalse(broken.isValid)
        guard case .invalidRegex = broken.patternProblem else {
            return XCTFail("括号未闭合必须报 invalidRegex，实际：\(String(describing: broken.patternProblem))")
        }
        let empty = TxtChapterRule(name: "空", pattern: "   ", priority: 1)
        XCTAssertEqual(empty.patternProblem, .empty)
        let long = TxtChapterRule(name: "过长", pattern: String(repeating: "a", count: 501), priority: 1)
        XCTAssertEqual(long.patternProblem, .tooLong)
    }

    func testLibraryDoesNotSplitVolumePassWhenActive() {
        var divider = LocalTxtSmartDivider()
        divider.ruleLibrary = TxtChapterRuleLibrary(isEnabled: true,
            rules: [rule("中文章节", #"^第\s*[0-9一二三四五六七八九十]+\s*[章回].*$"#, priority: 100)])
        let text = """
        第一卷 九州风雷
        第一章 潜龙勿用
        江水奔流不息。
        第二章 见龙在田
        群山耸立在远方。
        """
        let book = divider.divide(text: text, fileName: "Rule.txt")
        // 库接管后不再有内置的「卷」预处理：卷名这一行既不是标题也不是被丢弃的元数据，
        // 它按普通正文留在开篇的「引子」里。关键是没有任何章节标题被拼上卷前缀。
        XCTAssertEqual(book.chapters.count, 3)
        XCTAssertEqual(book.chapters[0].title, "引子")
        XCTAssertEqual(book.chapters[0].paragraphs, ["第一卷 九州风雷"])
        XCTAssertEqual(book.chapters[1].title, "第一章 潜龙勿用",
                       "库接管后不得再拼上用户没写进标题的卷前缀")
        XCTAssertEqual(book.chapters[1].paragraphs, ["江水奔流不息。"])
        XCTAssertEqual(book.chapters[2].title, "第二章 见龙在田")
        XCTAssertFalse(book.chapters.contains { $0.title.contains("第一卷") },
                       "卷名只能留在正文，不得进入任何章节标题")
    }

    func testLibraryRoundTripsThroughDefaults() {
        let suite = UserDefaults(suiteName: "TxtChapterRuleLibraryTests-\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.description) }
        var library = TxtChapterRuleLibrary.seeded
        library.isEnabled = true
        library.rules.append(rule("自定义", #"^§\d+.*$"#, priority: 999))
        library.save(to: suite)
        let loaded = TxtChapterRuleLibrary.load(from: suite)
        XCTAssertEqual(loaded, library)
        XCTAssertEqual(loaded.orderedEnabledRules.first?.name, "自定义")
    }

    func testEmptyPersistedStoreSeedsBuiltInsDisabled() {
        let suite = UserDefaults(suiteName: "TxtChapterRuleLibraryTests-empty-\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.description) }
        let loaded = TxtChapterRuleLibrary.load(from: suite)
        XCTAssertFalse(loaded.isEnabled)
        XCTAssertEqual(loaded.rules, TxtChapterRuleLibrary.seeded.rules)
        XCTAssertFalse(loaded.affectsImport)
    }
}
