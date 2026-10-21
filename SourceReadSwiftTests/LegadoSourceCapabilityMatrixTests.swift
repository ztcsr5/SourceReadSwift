import Foundation
import XCTest
@testable import SourceReadSwift

/// Static capability matrix for the 13-source Legado fixture.
/// This complements `LegadoCapabilityBankTests` (which locks labels/counts)
/// by proving every source decodes into the real `BookSource` model and that
/// the rule text survives with the constructs the engine must understand.
final class LegadoSourceCapabilityMatrixTests: XCTestCase {

    func testEveryFixtureSourceDecodesWithAllFourRuleStages() throws {
        let sources = try loadFixture()
        XCTAssertEqual(sources.count, 13)

        for raw in sources {
            let name = try XCTUnwrap(raw["bookSourceName"] as? String)
            let source = try decode(raw)

            XCTAssertFalse(source.bookSourceName.isEmpty, name)
            XCTAssertFalse(source.bookSourceUrl.isEmpty, name)
            XCTAssertNotNil(source.ruleSearch, "\(name): ruleSearch")
            XCTAssertNotNil(source.ruleBookInfo, "\(name): ruleBookInfo")
            XCTAssertNotNil(source.ruleToc, "\(name): ruleToc")
            XCTAssertNotNil(source.ruleContent, "\(name): ruleContent")

            XCTAssertNotNil(source.ruleSearch?.fields["bookList"] ?? source.ruleSearch?.raw, "\(name): bookList")
            XCTAssertNotNil(source.ruleToc?.fields["chapterList"] ?? source.ruleToc?.raw, "\(name): chapterList")
            XCTAssertNotNil(source.ruleContent?.fields["content"] ?? source.ruleContent?.raw, "\(name): content")
        }
    }

    func testLosslessRawKeepsTopLevelMetadata() throws {
        let sources = try loadFixture()
        let raw = try XCTUnwrap(sources.first { ($0["bookSourceName"] as? String) == "🔞🔲第一版主999" })
        let source = try decode(raw)

        XCTAssertEqual(source.raw["bookSourceName"], "🔞🔲第一版主999")
        XCTAssertNotNil(source.raw["bookSourceComment"])
        XCTAssertNotNil(source.raw["labels"])
        XCTAssertEqual(source.raw["complexity"], "C")
        XCTAssertNotNil(source.raw["searchUrl"])
        XCTAssertTrue(source.raw["searchUrl"]?.uppercased().contains("POST") == true)
    }

    func testHeavySourceExposesCryptoAndNetworkBridges() throws {
        let source = try source(named: "🔞🔲第一版主999")
        let text = try flattenedRuleText(source)

        for marker in ["createSymmetricCrypto", "md5Encode", "base64Decode",
                       "source.getVariable", "@js:", "GBK", "startBrowserAwait"] {
            XCTAssertTrue(text.contains(marker), "missing marker \(marker)")
        }
    }

    func testFanqieSourceExposesPutGetAndJSONPath() throws {
        let source = try source(named: "番茄小说")
        let text = try flattenedRuleText(source)

        for marker in ["@put", "@get", "$.", "java.", "@js:"] {
            XCTAssertTrue(text.contains(marker), "missing marker \(marker)")
        }
    }

    func testRegexAndCSSSourceKeepsSelectorPrefix() throws {
        let source = try source(named: "速读谷")
        let text = try flattenedRuleText(source)
        XCTAssertTrue(text.contains("@css:"))
        XCTAssertTrue(text.contains("##"))
        XCTAssertTrue(text.contains(":eq("))
    }

    func testFontObfuscatedSourceKeepsImageFontCleanupRule() throws {
        let source = try source(named: "风读小说")
        let text = try flattenedRuleText(source)
        // The fixture stores the rule as JSON with escaped slashes, so the
        // decoded rule text carries `\/asset\/fonts\/` (valid inside a JS
        // regex literal).  Assert the capability itself instead of one
        // particular escaping of it.
        XCTAssertTrue(text.contains("asset") && text.contains("fonts"))
        XCTAssertTrue(text.contains("<js>"))
    }

    func testPlainSourceHasNoJavaScriptRules() throws {
        let source = try source(named: "新版笔趣阁")
        let text = try flattenedRuleText(source)
        XCTAssertFalse(text.contains("@js:"))
        XCTAssertFalse(text.contains("<js>"))
        XCTAssertFalse(text.contains("java."))
    }

    func testGBKSourcesDeclareLegacyCharset() throws {
        let sources = try loadFixture().map { try decode($0) }
        let gbkNames = sources.filter { flattenedRuleTextUnsafe($0).uppercased().contains("GBK") }
            .map(\.bookSourceName)
            .sorted()
        XCTAssertEqual(gbkNames, ["希望中文", "第一版主网🔞", "📪第一版主820", "🔞🔲第一版主999"].sorted())
    }

    func testPagingCapabilityMatchesFixture() throws {
        let sources = try loadFixture().map { try decode($0) }
        var capabilities: [String: Set<String>] = [:]
        for source in sources {
            var caps: Set<String> = []
            if let next = source.ruleToc?.fields["nextTocUrl"],
               !next.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                caps.insert("tocNext")
            }
            if let next = source.ruleContent?.fields["nextContentUrl"],
               !next.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                caps.insert("contentNext")
            }
            if let search = source.searchUrl {
                if search.contains("{{page}}") {
                    caps.insert("searchPage")
                } else if search.range(of: "\\bpage\\b", options: .regularExpression) != nil {
                    caps.insert("searchPageVar")
                }
            }
            capabilities[source.bookSourceName] = caps
        }

        XCTAssertEqual(capabilities["第一版主网🔞"] ?? [], Set(["tocNext", "contentNext", "searchPage"]))
        XCTAssertEqual(capabilities["六月中文网"] ?? [], Set(["tocNext", "contentNext"]))
        XCTAssertEqual(capabilities["要撸小说"] ?? [], Set(["contentNext"]))
        XCTAssertEqual(capabilities["爱下电子书"] ?? [], Set(["searchPage"]))
        XCTAssertEqual(capabilities["番茄小说"] ?? [], Set(["searchPageVar"]))
        XCTAssertEqual(capabilities["久久小说网"] ?? [], Set<String>())
    }

    // MARK: - jsLib injection

    func testJSLibFromRawIsInjectedIntoJSCore() throws {
        let source = BookSource(
            bookSourceName: "jsLib",
            bookSourceUrl: "https://example.com",
            raw: ["jsLib": "let greet = function(){ return 'lib-ok'; };"]
        )
        let result = JSCoreRuntime().evaluate("greet();", variables: ["source": source])
        switch result {
        case .success(let value):
            XCTAssertEqual(value, "lib-ok")
        case .failure(let error):
            XCTFail("jsLib evaluation failed: \(error)")
        }
    }

    func testJSLibConstIsSanitizedAtLineStart() throws {
        let source = BookSource(
            bookSourceName: "jsLib-const",
            bookSourceUrl: "https://example.com",
            raw: ["jsLib": "const answer = 42;\nfunction getAnswer(){ return String(answer); }"]
        )
        let result = JSCoreRuntime().evaluate("getAnswer();", variables: ["source": source])
        switch result {
        case .success(let value):
            XCTAssertEqual(value, "42")
        case .failure(let error):
            XCTFail("jsLib const sanitization failed: \(error)")
        }
    }

    // MARK: - Helpers

    private func loadFixture() throws -> [[String: Any]] {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "legado-capability-bank-20260908", withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: "legado-capability-bank-20260908", withExtension: "json")
        )
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    private func decode(_ raw: [String: Any]) throws -> BookSource {
        try JSONDecoder().decode(BookSource.self, from: JSONSerialization.data(withJSONObject: raw))
    }

    private func source(named name: String) throws -> BookSource {
        let raw = try XCTUnwrap(loadFixture().first { ($0["bookSourceName"] as? String) == name })
        return try decode(raw)
    }

    private func flattenedRuleText(_ source: BookSource) throws -> String {
        flattenedRuleTextUnsafe(source)
    }

    private func flattenedRuleTextUnsafe(_ source: BookSource) -> String {
        var parts: [String] = []
        for rule in [source.ruleSearch, source.ruleBookInfo, source.ruleToc, source.ruleContent, source.ruleExplore] {
            guard let rule else { continue }
            if let raw = rule.raw { parts.append(raw) }
            for key in rule.fields.keys.sorted() {
                if let value = rule.fields[key] { parts.append(value) }
            }
        }
        parts.append(source.raw.values.joined(separator: "\n"))
        return parts.joined(separator: "\n")
    }
}