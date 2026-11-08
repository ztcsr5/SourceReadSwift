import XCTest
@testable import SourceReadSwift

@MainActor
final class PurifyRuleStoreTests: XCTestCase {
    func testImportsUniqueRulesAndPersistsEnabledState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = PurifyRulePersistence(fileManager: .default, rootURL: root)
        let store = PurifyRuleStore(persistence: persistence)

        store.add("广告.*##")
        let imported = store.importLines("""
        请收藏本站.*##
        广告.*##

        站点尾巴
        """)

        XCTAssertEqual(imported, 2)
        XCTAssertEqual(store.rules.map(\.pattern), ["请收藏本站.*##", "站点尾巴", "广告.*##"])

        let firstID = try XCTUnwrap(store.rules.first?.id)
        store.setEnabled(false, ruleID: firstID)

        let reloaded = PurifyRuleStore(persistence: persistence)
        XCTAssertEqual(reloaded.rules.map(\.pattern), ["请收藏本站.*##", "站点尾巴", "广告.*##"])
        XCTAssertEqual(reloaded.enabledPatterns, ["站点尾巴", "广告.*##"])
        try? FileManager.default.removeItem(at: root)
    }

    func testRemoveRulePersists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = PurifyRulePersistence(fileManager: .default, rootURL: root)
        let store = PurifyRuleStore(persistence: persistence)

        store.importLines("""
        A
        B
        """)
        let removedID = try XCTUnwrap(store.rules.first?.id)
        store.remove(ruleID: removedID)

        let reloaded = PurifyRuleStore(persistence: persistence)
        XCTAssertEqual(reloaded.rules.map(\.pattern), ["B"])
        try? FileManager.default.removeItem(at: root)
    }

    func testImportsPresetPatternsAndBulkToggles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = PurifyRulePersistence(fileManager: .default, rootURL: root)
        let store = PurifyRuleStore(persistence: persistence)
        let preset = PurifyRulePreset.builtIn[0]

        store.add(preset.patterns[0])
        let imported = store.importPatterns(preset.patterns)

        XCTAssertEqual(imported, preset.patterns.count - 1)
        XCTAssertTrue(store.containsPattern(preset.patterns[0]))
        XCTAssertEqual(store.enabledPatterns.count, preset.patterns.count)

        store.setAllEnabled(false)
        XCTAssertTrue(store.enabledPatterns.isEmpty)

        let reloaded = PurifyRuleStore(persistence: persistence)
        XCTAssertTrue(reloaded.enabledPatterns.isEmpty)

        reloaded.setAllEnabled(true)
        XCTAssertEqual(reloaded.enabledPatterns.count, preset.patterns.count)
        try? FileManager.default.removeItem(at: root)
    }

    func testPreviewUsesEnabledRulesAndIgnoresInvalidRegex() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = PurifyRulePersistence(fileManager: .default, rootURL: root)
        // Previously persisted invalid rules must remain recoverable and safe to preview.
        try persistence.save(["广告.*##", "[", "保留##替换"].map { PurifyRule(pattern: $0) })
        let store = PurifyRuleStore(persistence: persistence)

        XCTAssertEqual(store.preview(text: "正文\n广告内容\n保留"), "正文\n\n替换")
        XCTAssertEqual(store.validationErrors.count, 1)
        try? FileManager.default.removeItem(at: root)
    }

    func testInvalidImportIsAtomicAndReportsTheRuleToCorrect() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = PurifyRulePersistence(rootURL: root)
        let store = PurifyRuleStore(persistence: persistence)
        XCTAssertTrue(store.add("原规则##"))
        let original = store.rules
        XCTAssertEqual(store.importPatterns(["有效规则##", "[", "另一条##"]), 0)
        XCTAssertEqual(store.rules, original)
        XCTAssertEqual(try persistence.load(), original)
        XCTAssertTrue(store.lastError?.contains("第 2 条") == true)
        XCTAssertFalse(store.add("["))
        XCTAssertEqual(store.rules, original)
    }

    func testFailedSaveDoesNotChangeRulesOrReportAnImportCount() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = PurifyRulePersistence(rootURL: root)
        let store = PurifyRuleStore(persistence: persistence)
        XCTAssertTrue(store.add("已保存##"))
        let original = store.rules
        let file = root.appendingPathComponent("purify_rules.json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        XCTAssertFalse(store.add("新规则##"))
        XCTAssertEqual(store.importPatterns(["导入规则##"]), 0)
        store.setEnabled(false, ruleID: original[0].id)
        XCTAssertEqual(store.rules, original)
        store.remove(ruleID: original[0].id)
        XCTAssertEqual(store.rules, original)
        XCTAssertNotNil(store.lastError)
    }

    func testMultilineJavaScriptIsOneRuleAndValidationDoesNotExecuteIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PurifyRuleStore(persistence: PurifyRulePersistence(rootURL: root))
        let script = "@js:\nreturn result.replace(/广告/g, '');"
        XCTAssertEqual(store.importLines(script), 1)
        XCTAssertEqual(store.rules.map(\.pattern), [script])
        XCTAssertEqual(store.preview(text: "正文广告"), "正文")
        XCTAssertNil(PurifyRuleValidator.error(in: "@js: throw new Error('must not execute');"))
        XCTAssertNotNil(PurifyRuleValidator.error(in: "@js: }); globalThis.validationEscaped = true; (function(){"))
        XCTAssertNotNil(PurifyRuleValidator.error(in: "@js: return ("))
        XCTAssertNotNil(PurifyRuleValidator.error(in: "<js>result"))
        XCTAssertNotNil(PurifyRuleValidator.error(in: "##"))
        XCTAssertNil(PurifyRuleValidator.error(in: "##广告##替换"))
    }
}
