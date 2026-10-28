import XCTest
@testable import SourceReadSwift

/// QQ阅读 uses `.bookList[*]` against a response whose array lives under
/// `data`.  Legado's rjpath resolves that leading-dot path even though the key
/// is not on the root object, so list selection retries as a descendant scan.
final class JSONListDescendantTests: XCTestCase {
    private func object(_ json: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(json.utf8))
    }

    func testLeadingDotListFallsBackToDescendantScan() throws {
        let payload = try object(#"{"code":0,"data":{"bookList":[{"title":"A"},{"title":"B"}]}}"#)

        let rows = JSONRuleExtractor().list(from: payload, rule: ".bookList[*]")

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.compactMap { $0["title"] as? String }, ["A", "B"])
    }

    func testDirectListPathWinsOverDescendantScan() throws {
        let payload = try object(#"{"bookList":[{"title":"A"}],"data":{"bookList":[{"title":"X"},{"title":"Y"}]}}"#)

        let rows = JSONRuleExtractor().list(from: payload, rule: ".bookList[*]")

        XCTAssertEqual(rows.count, 1, "a direct root match must not be replaced by descendant matches")
        XCTAssertEqual(rows.first?["title"] as? String, "A")
    }
}
