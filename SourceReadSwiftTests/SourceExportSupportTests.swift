import XCTest
@testable import SourceReadSwift

final class SourceExportSupportTests: XCTestCase {
    func testExportRoundTripsAuthoritativeAndExtraLegadoFields() throws {
        let source = BookSource(
            bookSourceName: "测试书源 / A",
            bookSourceUrl: "https://example.com/book",
            bookSourceGroup: "精品,玄幻",
            bookSourceType: 0,
            enabled: false,
            weight: 12,
            searchUrl: "https://example.com/search?q={{key}}",
            ruleSearch: SourceRule(fields: ["bookList": ".item", "name": "a@text"]),
            ruleContent: SourceRule(fields: ["content": "#content@html"]),
            raw: [
                "bookSourceComment": "仅测试使用",
                "jsLib": "function ping() { return 'ok'; }",
                "enabledCookieJar": "true",
                "customOrder": "42",
                "enabled": "true"
            ]
        )

        let jsonString = try SourceBookExportSupport.jsonString(for: [source])
        XCTAssertFalse(jsonString.contains("\"raw\""))
        XCTAssertTrue(jsonString.contains("\"bookSourceComment\" : \"仅测试使用\""))

        let data = try XCTUnwrap(jsonString.data(using: .utf8))
        let decoded = try JSONDecoder().decode([BookSource].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        let restored = try XCTUnwrap(decoded.first)
        XCTAssertEqual(restored.bookSourceName, "测试书源 / A")
        XCTAssertEqual(restored.bookSourceUrl, "https://example.com/book")
        XCTAssertEqual(restored.bookSourceGroup, "精品,玄幻")
        XCTAssertFalse(restored.enabled)
        XCTAssertEqual(restored.weight, 12)
        XCTAssertEqual(restored.ruleSearch?.fields["bookList"], ".item")
        XCTAssertEqual(restored.raw["jsLib"], "function ping() { return 'ok'; }")
        XCTAssertEqual(restored.raw["bookSourceComment"], "仅测试使用")
        XCTAssertEqual(restored.raw["enabledCookieJar"], "true")
    }

    func testExportRejectsEmptySourceArray() {
        XCTAssertThrowsError(try SourceBookExportSupport.jsonData(for: [])) { error in
            XCTAssertEqual(error as? SourceExportError, .emptySources)
        }
    }

    func testSuggestedFileNameSanitizesForbiddenCharacters() {
        let source = BookSource(bookSourceName: "测:试/书*源?", bookSourceUrl: "https://a.example")
        let singleName = SourceBookExportSupport.suggestedFileName(for: [source])
        XCTAssertEqual(singleName, "测_试_书_源_.json")

        let forbiddenOnly = BookSource(bookSourceName: "?:/", bookSourceUrl: "https://fallback.example")
        XCTAssertEqual(SourceBookExportSupport.suggestedFileName(for: [forbiddenOnly]), "book_source.json")

        let second = BookSource(bookSourceName: "第二源", bookSourceUrl: "https://b.example")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let batchName = SourceBookExportSupport.suggestedFileName(for: [source, second], label: "已选", date: date)
        XCTAssertTrue(batchName.hasPrefix("书源导出_已选_2个_"))
        XCTAssertTrue(batchName.hasSuffix(".json"))
    }

    func testWriteTemporaryJSONFileWritesDecodableFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ExportTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let sources = [
            BookSource(bookSourceName: "源一", bookSourceUrl: "https://one.example"),
            BookSource(bookSourceName: "源二", bookSourceUrl: "https://two.example")
        ]
        let fileURL = try SourceBookExportSupport.writeTemporaryJSONFile(for: sources, label: "全部", directory: dir)
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode([BookSource].self, from: data)
        XCTAssertEqual(decoded.map(\.bookSourceUrl), ["https://one.example", "https://two.example"])
    }

    func testSelectionStateHelperHidesBatchToolbarAndClearsSelectionsWhenEmpty() {
        XCTAssertFalse(SourceSelectionStateHelper.shouldShowBatchToolbar(isManaging: true, totalCount: 0))
        XCTAssertFalse(SourceSelectionStateHelper.shouldShowBatchToolbar(isManaging: false, totalCount: 5))
        XCTAssertTrue(SourceSelectionStateHelper.shouldShowBatchToolbar(isManaging: true, totalCount: 2))

        XCTAssertFalse(SourceSelectionStateHelper.reconciledManagingState(true, totalCount: 0))
        XCTAssertTrue(SourceSelectionStateHelper.reconciledManagingState(true, totalCount: 1))

        XCTAssertEqual(
            SourceSelectionStateHelper.reconciledSelection(["a", "b", "c"], validIDs: ["b", "d"]),
            ["b"]
        )
        XCTAssertEqual(
            SourceSelectionStateHelper.reconciledSelection(["a"], validIDs: []),
            []
        )
    }
}
