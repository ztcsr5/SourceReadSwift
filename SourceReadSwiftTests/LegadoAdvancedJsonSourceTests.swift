import Foundation
import XCTest
@testable import SourceReadSwift

final class LegadoAdvancedJsonSourceTests: XCTestCase {

    func testJsonRuleExtractorWithAtJsonPrefix() {
        let extractor = JSONRuleExtractor()
        let json: [String: Any] = [
            "code": 0,
            "data": [
                "list": [
                    ["title": "诡秘之主", "id": "1001"],
                    ["title": "宿命之环", "id": "1002"]
                ]
            ]
        ]

        let items = extractor.list(from: json, rule: "@json:$.data.list[*]")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(extractor.string(from: items[0], rule: "@json:$.title", fallbackKeys: ["title"]), "诡秘之主")
        XCTAssertEqual(extractor.string(from: items[1], rule: "@json:$.id", fallbackKeys: ["id"]), "1002")
    }

    func testChainedJsAndJsonPathExtraction() {
        let extractor = JSONRuleExtractor()
        // Simulates Tomato novel bookList rule: <js>...JSON.stringify(book_list)</js>$[*]
        let rawResponse: [String: Any] = [
            "data": [
                "search_data": [
                    [
                        "books": [
                            ["book_name": "十日终焉（别名：终焉之日）", "book_id": "7123456", "author": "杀虫队队员"]
                        ]
                    ]
                ]
            ]
        ]

        let jsRule = """
        <js>
        let res = result;
        let book_list = [];
        if (res.data.search_data) {
          for (let item of res.data.search_data) {
            if (item.books && Array.isArray(item.books)) {
              book_list = book_list.concat(item.books);
            }
          }
        }
        JSON.stringify(book_list)
        </js>$[*]
        """

        let books = extractor.list(from: rawResponse, rule: jsRule)
        XCTAssertEqual(books.count, 1)

        // Test 2-part regex: name##（别名：.*?）
        let nameRule = "book_name##（别名：.*?）"
        let name = extractor.string(from: books[0], rule: nameRule, fallbackKeys: ["name"])
        XCTAssertEqual(name, "十日终焉")

        let bookId = extractor.string(from: books[0], rule: "{{$.book_id}}", fallbackKeys: ["book_id"])
        XCTAssertEqual(bookId, "7123456")
    }

    func testVolumeAndChapterFlattening() {
        let extractor = JSONRuleExtractor()
        // Simulates Tomato novel TOC: $.data.chapterListWithVolume[*].*
        let tocResponse: [String: Any] = [
            "data": [
                "chapterListWithVolume": [
                    [
                        "volume_name": "第一卷",
                        "chapters": [
                            ["title": "第1章 生肖", "itemId": "101"],
                            ["title": "第2章 规则", "itemId": "102"]
                        ]
                    ],
                    [
                        "volume_name": "第二卷",
                        "chapters": [
                            ["title": "第3章 终局", "itemId": "103"]
                        ]
                    ]
                ]
            ]
        ]

        let chapters = extractor.list(from: tocResponse, rule: "$.data.chapterListWithVolume[*].*")
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(extractor.string(from: chapters[0], rule: "$.title", fallbackKeys: ["title"]), "第1章 生肖")
        XCTAssertEqual(extractor.string(from: chapters[2], rule: "$.title", fallbackKeys: ["title"]), "第3章 终局")
    }

    func testLeadingRegexReplacement() {
        let replaced = PurifyRuleEvaluator.apply(rule: "##\"$##", to: "正文内容\"")
        XCTAssertEqual(replaced, "正文内容")
    }

    func testJSONPUnwrapping() {
        let jsonp = "callback_123({\"status\":1,\"data\":{\"title\":\"JSONP小说\"}\n})"
        let parsed = ResponseFormatDetector.jsonObject(from: jsonp)
        XCTAssertNotNil(parsed)
        guard let dict = parsed as? [String: Any],
              let data = dict["data"] as? [String: Any] else {
            return XCTFail("expected dict")
        }
        XCTAssertEqual(data["title"] as? String, "JSONP小说")
    }

    func testJavaGetStringOnJSON() {
        let runtime = JSCoreRuntime()
        let jsonText = "{\"book_search_visible\":\"true\",\"last_chapter_update_time\":1700000000}"
        let script = """
        var visible = java.getString(html, '$.book_search_visible');
        var time = java.getString(html, 'last_chapter_update_time');
        visible + '|' + time;
        """
        let res = runtime.evaluate(script, variables: ["html": jsonText])
        guard case .success(let val) = res else {
            return XCTFail("evaluation failed: \(res)")
        }
        XCTAssertEqual(val, "true|1700000000")
    }
}
