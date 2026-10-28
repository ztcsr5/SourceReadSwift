import XCTest
import SwiftSoup
@testable import SourceReadSwift

/// Legado index lists are richer than "pick these positions": they accept
/// ranges with omitted bounds (`[8:]`, `[1:-1]`), steps (`[3:-2:-10]`),
/// reverse ranges (`[-1:0]`) and exclusions (`[!1,2,-2]`).  These tests pin
/// the parser and the executed element sets against the semantics of
/// `AnalyzeByJSoup.ElementsSingle.findIndexSet`.
final class LegadoIndexSyntaxTests: XCTestCase {
    private func makeListHTML(_ count: Int) -> String {
        (0..<count).map { "<li id=\"i\($0)\">\($0)</li>" }.joined()
    }

    private func ids(_ elements: [Element]) -> [String] {
        elements.compactMap { try? $0.attr("id") }
    }

    private func execute(_ rule: String, count: Int = 10) throws -> [String] {
        let doc = try SwiftSoup.parse("<ul>\(makeListHTML(count))</ul>")
        let root = try XCTUnwrap(doc.body())
        let steps = LegadoDefaultRuleTranslator.translateSelectorSteps(rule)
        return ids(LegadoDefaultRuleTranslator.executeSteps(steps, on: root))
    }

    func testParseRangeForms() throws {
        let trailing = LegadoDefaultRuleTranslator.parseIndexItems("8:")
        XCTAssertEqual(trailing?.items, [.range(start: 8, end: nil, step: 1)])

        let closed = LegadoDefaultRuleTranslator.parseIndexItems("1:-1")
        XCTAssertEqual(closed?.items, [.range(start: 1, end: -1, step: 1)])

        let stepped = LegadoDefaultRuleTranslator.parseIndexItems("3:-2:-10")
        XCTAssertEqual(stepped?.items, [.range(start: 3, end: -2, step: -10)])

        let mixed = LegadoDefaultRuleTranslator.parseIndexItems("-1, 3:-2:-10, 2")
        XCTAssertEqual(mixed?.items, [
            .single(-1),
            .range(start: 3, end: -2, step: -10),
            .single(2)
        ])

        let excluded = LegadoDefaultRuleTranslator.parseIndexItems("!1,2,-2")
        XCTAssertEqual(excluded?.isExclude, true)
        XCTAssertEqual(excluded?.items, [.single(1), .single(2), .single(-2)])

        XCTAssertNil(LegadoDefaultRuleTranslator.parseIndexItems(""))
        XCTAssertNil(LegadoDefaultRuleTranslator.parseIndexItems("a:b"))
    }

    func testBracketRangeTranslation() throws {
        let steps = LegadoDefaultRuleTranslator.translateSelectorSteps("li[1:-1]")
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].selector, "li")
        XCTAssertEqual(steps[0].indexItems, [.range(start: 1, end: -1, step: 1)])
        XCTAssertNil(steps[0].indices, "a range cannot be flattened without an element count")
    }

    func testExecuteTrailingRange() throws {
        XCTAssertEqual(try execute("ul li[8:]"), ["i8", "i9"])
    }

    func testExecuteInnerRangeExcludesLast() throws {
        XCTAssertEqual(try execute("ul li[1:-1]"), (1...8).map { "i\($0)" })
    }

    func testExecuteOverflowRangeKeepsLast() throws {
        XCTAssertEqual(try execute("ul li[12:-1]"), ["i9"])
    }

    func testExecuteReverseRange() throws {
        XCTAssertEqual(try execute("ul li[-1:0]"), (0...9).reversed().map { "i\($0)" })
    }

    func testExecuteExclusionList() throws {
        XCTAssertEqual(try execute("ul li[!1,2,-2]"), ["i0", "i3", "i4", "i5", "i6", "i7", "i9"])
    }

    func testExecutePlainList() throws {
        XCTAssertEqual(try execute("ul li[3,4]", count: 6), ["i3", "i4"])
    }

    func testLegacyColonSeparatorMeansSeparateIndices() throws {
        // Outside brackets Legado treats `:` as a separator, not a range:
        // `li.1:3` picks the 2nd and 4th element, never 1,2,3.
        let parsed = LegadoDefaultRuleTranslator.parseIndexItems("1:3", allowRanges: false)
        XCTAssertEqual(parsed?.items, [.single(1), .single(3)])
        XCTAssertEqual(try execute("ul li.1:3"), ["i1", "i3"])
    }

    func testExecuteStepInterval() throws {
        // 0:9:3 -> 0, 3, 6, 9 under Legado's inclusive range semantics.
        XCTAssertEqual(try execute("ul li[0:9:3]"), ["i0", "i3", "i6", "i9"])
    }
}
