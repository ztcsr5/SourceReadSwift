import XCTest
@testable import SourceReadSwift

final class RuleOperatorSplitterTests: XCTestCase {
    func testSplitKeepsLegacyNilSemantics() {
        XCTAssertEqual(RuleOperatorSplitter.split("a&&b&&c", separator: "&&"), ["a", "b", "c"])
        XCTAssertNil(RuleOperatorSplitter.split("a&&b", separator: "||"))
        XCTAssertNil(RuleOperatorSplitter.split("", separator: "&&"))
    }

    func testFirstOperatorIgnoresQuotedOperators() {
        let result = RuleOperatorSplitter.firstOperator(in: #"$['data']['a&&b'] || $.fallback"#)
        XCTAssertEqual(result?.op, "||")
        XCTAssertEqual(result?.parts, [#"$['data']['a&&b']"#, "$.fallback"])
    }

    func testFirstOperatorIgnoresFilterAndPutBraces() {
        let filter = RuleOperatorSplitter.firstOperator(in: "$.list[?(@.a==1&&@.b==2)] || $.fallback")
        XCTAssertEqual(filter?.op, "||")
        XCTAssertEqual(filter?.parts.count, 2)

        let put = RuleOperatorSplitter.firstOperator(in: "@put:{k:$.a&&b}%%$.c")
        XCTAssertEqual(put?.op, "%%")
        XCTAssertEqual(put?.parts.count, 2)
    }

    func testFirstOperatorWinsInSourceOrder() {
        let result = RuleOperatorSplitter.firstOperator(in: "a&&b||c")
        XCTAssertEqual(result?.op, "&&")
        XCTAssertEqual(result?.parts, ["a", "b||c"])
    }

    func testSameOperatorSplitsEveryTopLevelOccurrence() {
        let result = RuleOperatorSplitter.firstOperator(in: "a%%b%%c")
        XCTAssertEqual(result?.op, "%%")
        XCTAssertEqual(result?.parts, ["a", "b", "c"])
    }
}
