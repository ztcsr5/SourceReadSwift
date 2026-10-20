import XCTest
import SwiftSoup
@testable import SourceReadSwift

final class RuleDirectiveParserTests: XCTestCase {
    func testPutBodyKeepsQuotedBraceAndSplitsFields() {
        let pairs = RuleDirectiveParser.parsePutBody(#"a:$.x,b:"}""#)
        let map = Dictionary(uniqueKeysWithValues: pairs.map { ($0.key, $0.valueRule) })

        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(map["a"], "$.x")
        XCTAssertEqual(map["b"], "}")
    }

    func testPutBodyKeepsRegexBracesOpaque() {
        let pairs = RuleDirectiveParser.parsePutBody(#"re:##\}$##,name:$.name"#)
        let map = Dictionary(uniqueKeysWithValues: pairs.map { ($0.key, $0.valueRule) })

        XCTAssertEqual(map["re"], #"##\}$##"#)
        XCTAssertEqual(map["name"], "$.name")
    }

    func testPutBodyKeepsNestedObjectValueIntact() {
        let pairs = RuleDirectiveParser.parsePutBody(#"obj:{"a":{"b":1}},name:$.name"#)
        let map = Dictionary(uniqueKeysWithValues: pairs.map { ($0.key, $0.valueRule) })

        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(map["obj"], #"{"a":{"b":1}}"#)
        XCTAssertEqual(map["name"], "$.name")
    }

    func testPutBodyAcceptsJSONObjectForm() {
        let pairs = RuleDirectiveParser.parsePutBody(#"{"key":"$.data.token","other":"$.data.other"}"#)
        let map = Dictionary(uniqueKeysWithValues: pairs.map { ($0.key, $0.valueRule) })

        XCTAssertEqual(map["key"], "$.data.token")
        XCTAssertEqual(map["other"], "$.data.other")
    }

    func testSpansFindEveryPutDirective() {
        let rule = #"@put:{a:$.x}@put:{b:$.y}title"#
        let bodies = RuleDirectiveParser.spans(in: rule, marker: "@put:").map(\.body)

        XCTAssertEqual(bodies, ["a:$.x", "b:$.y"])
    }

    func testRemovingPutsKeepsRemainingRule() {
        let rule = #"@put:{a:$.x,b:"}"}.title@text"#

        XCTAssertEqual(RuleDirectiveParser.removingPuts(from: rule), ".title@text")
    }

    func testReplacingGetsSupportsBracedBareAndTrailingText() {
        let braced = RuleDirectiveParser.replacingGets(in: "@get:{a}/book/1") { $0 == "a" ? "HOST" : "" }
        let bare = RuleDirectiveParser.replacingGets(in: #"@get:b##\d+##"#) { $0 == "b" ? "TOKEN" : "" }
        let mixed = RuleDirectiveParser.replacingGets(in: "@get:{a}@get:b") { $0 == "a" ? "A" : "B" }

        XCTAssertEqual(braced, "HOST/book/1")
        XCTAssertEqual(bare, #"TOKEN##\d+##"#)
        XCTAssertEqual(mixed, "AB")
    }

    func testPersistentStateEnumeratesObjectOnlyKeys() {
        let state = RulePersistentState()
        state.putObject(["name": "reader"], for: "source.login.user")
        state.put("token", for: "source.login.token")

        XCTAssertEqual(state.keys(withPrefix: "source.login."), ["source.login.token", "source.login.user"])
        XCTAssertEqual(state.snapshot(), ["source.login.token": "token"])

        state.removePrefix("source.login.")
        XCTAssertEqual(state.keys(withPrefix: "source.login."), [])
        XCTAssertNil(state.object(for: "source.login.user"))
    }

    func testHtmlPutMultipleFieldsAndCrossInstanceGet() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <span class="host">https://example.com</span>
          <span class="path">/book/1</span>
        </body></html>
        """)
        let state = RulePersistentState()
        let baseURL = URL(string: "https://example.com/search")!

        let first = HtmlRuleExtractor(executionContext: RuleExecutionContext(persistentState: state))
        let host = try first.value(
            from: document,
            rule: #"@put:{host:.host@text,path:.path@text}.host@text"#,
            baseUrl: baseURL
        )
        XCTAssertEqual(host, "https://example.com")

        let second = HtmlRuleExtractor(executionContext: RuleExecutionContext(persistentState: state))
        XCTAssertEqual(try second.value(from: document, rule: "@get:{path}", baseUrl: baseURL), "/book/1")
    }

    func testJSONPutWithNestedValueSurvivesAcrossContexts() {
        let state = RulePersistentState()
        let object: [String: Any] = [
            "data": [
                "payload": ["a": ["b": 1]],
                "token": "abc"
            ]
        ]

        let first = JSONRuleExtractor(executionContext: RuleExecutionContext(persistentState: state))
        _ = first.value(from: object, path: #"@put:{payload:$.data.payload,token:$.data.token}$.data.token"#)

        let second = JSONRuleExtractor(executionContext: RuleExecutionContext(persistentState: state))
        XCTAssertEqual(second.value(from: [:], path: "@get:{token}") as? String, "abc")
        let payload = second.value(from: [:], path: "@get:{payload}") as? [String: Any]
        XCTAssertEqual((payload?["a"] as? [String: Any])?["b"] as? Int, 1)
    }
}
