import XCTest
@testable import SourceReadSwift

/// Regression coverage for three engine defects found while auditing the
/// 76-source private bank (1.0.90).  Each case mirrors a real rule shape from
/// `shareBookSource11.json` so a future refactor cannot silently reintroduce
/// the failure.
final class SourceEnginePerBookVariablesTests: XCTestCase {

    // MARK: - 1. Qimao: `{{$.id}}` inside an `@js:` rule

    func testJSONBookURLInterpolatesJSONPathTemplateInsideJSRule() throws {
        let item: [String: Any] = ["id": 1784900, "title": "斗破苍穹"]
        let rule = """
        @js:
        var params = { id: {{$.id}}, imei_ip: '2937357107', teeny_mode: 0 };
        JSON.stringify(params)
        """

        let value = try XCTUnwrap(JSONRuleExtractor().string(from: item, rule: rule, fallbackKeys: []))
        XCTAssertFalse(value.contains("{{"), "placeholder must be expanded before JS runs: \(value)")

        let data = try XCTUnwrap(value.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((object["id"] as? NSNumber)?.intValue, 1784900)
        XCTAssertEqual(object["imei_ip"] as? String, "2937357107")
        XCTAssertEqual((object["teeny_mode"] as? NSNumber)?.intValue, 0)
    }

    // MARK: - 2. Baidu: bare `gid@js:` prefix must evaluate against the JSON doc

    func testDynamicURLResolverEvaluatesBareFieldPrefixBeforeJS() {
        let source = BookSource(bookSourceName: "百度小说", bookSourceUrl: "https://spapi.baidu.com")
        let context = RuleExecutionContext()
        let gid = "975E42D44FDA5B9F2642937297834CE9DC39F62463A1"
        let rule = #"gid@js:'/searchbox?action=novel&type=chapter,'+JSON.stringify({"method":"POST","body":'data={"gid":'+result+'}'})"#

        let resolved = DynamicURLResolver.resolve(
            rule,
            baseUrl: "https://spapi.baidu.com/",
            source: source,
            variables: ["result": ["gid": gid, "title": "测试"]],
            context: context
        )

        XCTAssertTrue(resolved.contains(gid), "bare `gid` was not evaluated: \(resolved)")
        XCTAssertTrue(resolved.contains("data={" + "\"gid\":\"\(gid)\""), "unexpected body: \(resolved)")
        XCTAssertFalse(resolved.contains("data={\"gid\":gid}"), "literal rule text leaked into URL: \(resolved)")
    }

    // MARK: - 3. Aishuyin: per-row java.put values survive the last row

    func testSearchResultParserCapturesPerRowVariablesForBookURL() throws {
        let source = BookSource(
            bookSourceName: "爱书音",
            bookSourceUrl: "https://m.shuyinfm.com",
            ruleSearch: SourceRule(fields: [
                "bookList": "$.books[*]",
                "name": "$.title",
                "author": "$.author",
                "bookUrl": """
                @js:
                (function() {
                    var id = result.id || '';
                    var source = String(result.source || '').trim();
                    java.put('source', source);
                    java.put('id', id);
                    return 'https://api.example.com/detail/' + id + '?source=' + source;
                })()
                """
            ])
        )
        let body = #"{"books":[{"title":"甲","author":"A","id":"a1","source":"kuwo"},{"title":"乙","author":"B","id":"b1","source":"bilibili"}]}"#
        let response = SourceResponse(
            url: URL(string: "https://m.shuyinfm.com/api/search/all?keyword=x")!,
            statusCode: 200,
            headers: [:],
            body: body,
            data: Data(body.utf8)
        )
        let context = RuleExecutionContext()
        var parser = SearchResultParser(executionContext: context)
        var captured: [String: [String: String]] = [:]
        parser.onBookVariables = { url, delta in captured[url] = delta }

        let result = parser.parse(source: source, response: response)

        guard case .success(let books) = result else {
            return XCTFail("expected parsed books, got \(result)")
        }
        XCTAssertEqual(books.count, 2)
        XCTAssertEqual(captured["https://api.example.com/detail/a1?source=kuwo"]?["id"] ?? "", "a1")
        XCTAssertEqual(captured["https://api.example.com/detail/a1?source=kuwo"]?["source"] ?? "", "kuwo")
        XCTAssertEqual(captured["https://api.example.com/detail/b1?source=bilibili"]?["id"] ?? "", "b1")
        XCTAssertEqual(captured["https://api.example.com/detail/b1?source=bilibili"]?["source"] ?? "", "bilibili")
        XCTAssertEqual(context.persistentSnapshot()["id"] ?? "", "b1", "last row still owns the live context; per-row deltas are what the engine replays later")
    }
}
