import XCTest
import SwiftSoup
@testable import SourceReadSwift

final class RuleTransformParserTests: XCTestCase {
    func testSplitTwoFieldsMeansRemoveAllMatches() {
        let split = RuleTransformParser.split("$.text##a")
        XCTAssertEqual(split.path, "$.text")
        XCTAssertEqual(
            split.transform,
            RuleRegexTransform(pattern: "a", replacement: "", replaceFirst: false)
        )
    }

    func testSplitThreeFieldsUsesReplacement() {
        let split = RuleTransformParser.split("$.text##a##b")
        XCTAssertEqual(split.path, "$.text")
        XCTAssertEqual(
            split.transform,
            RuleRegexTransform(pattern: "a", replacement: "b", replaceFirst: false)
        )
    }

    func testSplitFourFieldsEnablesReplaceFirst() {
        let split = RuleTransformParser.split("$.text##(\\d+)##[$1]##flag")
        XCTAssertEqual(split.path, "$.text")
        XCTAssertEqual(split.transform?.pattern, "(\\d+)")
        XCTAssertEqual(split.transform?.replacement, "[$1]")
        XCTAssertEqual(split.transform?.replaceFirst, true)
    }

    func testSplitIgnoresFieldsAfterFourth() {
        let split = RuleTransformParser.split("$.text##a##b##c##d")
        XCTAssertEqual(
            split.transform,
            RuleRegexTransform(pattern: "a", replacement: "b", replaceFirst: true)
        )
    }

    func testEmptyPatternProducesNoTransform() {
        let split = RuleTransformParser.split("$.text####x")
        XCTAssertEqual(split.path, "$.text")
        XCTAssertNil(split.transform)
    }

    func testPathIsTrimmedLikeLegado() {
        let split = RuleTransformParser.split("  $.text  ##a##b  ")
        XCTAssertEqual(split.path, "$.text")
        XCTAssertEqual(split.transform?.replacement, "b  ")
    }

    func testApplyReplaceAll() {
        let transform = RuleRegexTransform(pattern: "a", replacement: "b", replaceFirst: false)
        XCTAssertEqual(RuleTransformParser.apply(transform, to: "a a a"), "b b b")
    }

    func testApplyReplaceFirstReturnsReplacedMatchOnly() {
        let transform = RuleRegexTransform(
            pattern: "(第\\d+章)",
            replacement: "【$1】",
            replaceFirst: true
        )
        XCTAssertEqual(RuleTransformParser.apply(transform, to: "第1章 开始"), "【第1章】")
    }

    func testApplyReplaceFirstWithoutMatchReturnsEmptyString() {
        let transform = RuleRegexTransform(pattern: "xyz", replacement: "b", replaceFirst: true)
        XCTAssertEqual(RuleTransformParser.apply(transform, to: "a a a"), "")
    }

    func testApplyInvalidPatternFallsBackToLiteralReplace() {
        let transform = RuleRegexTransform(pattern: "a(", replacement: "X", replaceFirst: false)
        XCTAssertEqual(RuleTransformParser.apply(transform, to: "a(b"), "Xb")
    }

    func testApplyInvalidPatternReplaceFirstReturnsReplacement() {
        let transform = RuleRegexTransform(pattern: "a(", replacement: "X", replaceFirst: true)
        XCTAssertEqual(RuleTransformParser.apply(transform, to: "a(b"), "X")
    }

    func testHTMLAndJSONShareTransformSemantics() throws {
        let rule = "p@text##(第\\d+章)##【$1】"
        let document = try SwiftSoup.parse("<p>第1章 开始</p>")
        let htmlValue = try HtmlRuleExtractor().value(
            from: document,
            rule: rule,
            baseUrl: URL(string: "https://example.com")!
        )
        let jsonValue = JSONRuleExtractor().value(
            from: ["text": "第1章 开始"],
            path: "$.text##(第\\d+章)##【$1】"
        ) as? String

        XCTAssertEqual(htmlValue, "【第1章】 开始")
        XCTAssertEqual(jsonValue, "【第1章】 开始")
    }

    func testHTMLFourFieldTransformUsesReplaceFirst() throws {
        let document = try SwiftSoup.parse("<p>第1章 开始</p>")
        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: "p@text##(第\\d+章)##【$1】##1",
            baseUrl: URL(string: "https://example.com")!
        )
        XCTAssertEqual(value, "【第1章】")
    }

    func testJSONFourFieldTransformUsesReplaceFirst() {
        let value = JSONRuleExtractor().value(
            from: ["text": "第1章 开始"],
            path: "$.text##(第\\d+章)##【$1】##1"
        ) as? String
        XCTAssertEqual(value, "【第1章】")
    }
}