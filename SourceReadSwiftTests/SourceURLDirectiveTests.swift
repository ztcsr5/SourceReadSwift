import XCTest
@testable import SourceReadSwift

final class SourceURLDirectiveTests: XCTestCase {
    func testParseHeaderDirective() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/search@Header:{"Referer":"https://example.com","X-Test":"1"}"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/search")
        XCTAssertEqual(directive.headers["Referer"], "https://example.com")
        XCTAssertEqual(directive.headers["X-Test"], "1")
        XCTAssertEqual(directive.method, .get)
    }

    func testParseJSONPostDirective() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api,{"method":"POST","body":"keyword=test","headers":{"Content-Type":"application/x-www-form-urlencoded"}}"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/api")
        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "keyword=test")
        XCTAssertEqual(directive.headers["Content-Type"], "application/x-www-form-urlencoded")
    }

    func testParseHeaderThenBodyDirectives() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api@Header:{"Referer":"https://example.com"}@Body:q=1"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/api")
        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "q=1")
        XCTAssertEqual(directive.headers["Referer"], "https://example.com")
    }

    func testParseBodyThenHeaderDirectives() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api@Body:q=1@Header:{"Referer":"https://example.com"}"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/api")
        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "q=1")
        XCTAssertEqual(directive.headers["Referer"], "https://example.com")
    }

    func testParseHeaderAndPostAliases() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api@Headers:{"X-Test":"1"}@Post:q=1"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/api")
        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "q=1")
        XCTAssertEqual(directive.headers["X-Test"], "1")
    }

    func testParseJSONAliases() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api,{"httpMethod":"POST","requestBody":"keyword=test","bookSourceHeader":{"X-Book":"1"}}"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/api")
        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "keyword=test")
        XCTAssertEqual(directive.headers["X-Book"], "1")
    }

    func testParseDictionaryBodyAsFormBodyByDefault() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api,{"body":{"b":"2","a":"1&2"}}"#
        )

        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "a=1%262&b=2")
    }

    func testParseDictionaryBodyAsJSONWhenContentTypeIsJSON() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api,{"headers":{"Content-Type":"application/json"},"body":{"b":"2","a":"1"}}"#
        )

        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), #"{"a":"1","b":"2"}"#)
    }

    func testParseLegadoTypeAndDataAliases() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api,{"type":"POST","data":{"q":"test","page":"2"}}"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/api")
        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "page=2&q=test")
    }

    func testParseJSONHeadDirectiveWithoutBody() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/health,{"method":"HEAD","headers":{"X-Probe":"1"}}"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/health")
        XCTAssertEqual(directive.method, .head)
        XCTAssertNil(directive.body)
        XCTAssertEqual(directive.headers["X-Probe"], "1")
    }

    func testParseCharsetAndEncodingTrailingDirectives() {
        let charset = SourceURLDirectiveParser().parse(
            #"https://example.com/search@Charset:gbk"#
        )
        XCTAssertEqual(charset.urlText, "https://example.com/search")
        XCTAssertEqual(charset.expectedCharset, "gbk")

        let encoding = SourceURLDirectiveParser().parse(
            #"https://example.com/search@Encoding:UTF-8"#
        )
        XCTAssertEqual(encoding.expectedCharset, "UTF-8")
    }

    func testParseJSONTimeoutOptionsAsSecondsOrMilliseconds() {
        let seconds = SourceURLDirectiveParser().parse(
            #"https://example.com/search,{"timeout":2}"#
        )
        XCTAssertEqual(seconds.timeout ?? -1, 2, accuracy: 0.001)

        let milliseconds = SourceURLDirectiveParser().parse(
            #"https://example.com/search,{"timeoutMs":1500}"#
        )
        XCTAssertEqual(milliseconds.timeout ?? -1, 1.5, accuracy: 0.001)
    }

    func testParsePlainHeaderAndEscapedBody() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api@Header:X-Test: 1\nReferer: https://example.com\n@Body:a=1\nb=2"#
        )

        XCTAssertEqual(directive.headers["X-Test"], "1")
        XCTAssertEqual(directive.headers["Referer"], "https://example.com")
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "a=1\nb=2")
        XCTAssertEqual(directive.method, .post)
    }

    func testParseEscapedBodyAndCharsetTogether() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api@Charset:gbk@Body:q=hello\npage=2"#
        )

        XCTAssertEqual(directive.expectedCharset, "gbk")
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "q=hello\npage=2")
        XCTAssertEqual(directive.method, .post)
    }

    func testParseJSONBodyPreservesNumbersAndBooleans() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api,{"headers":{"Content-Type":"application/json"},"body":{"page":2,"enabled":true}}"#
        )

        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), #"{"enabled":true,"page":2}"#)
    }

    // MARK: - 1.0.77 relaxed option objects (real source shapes)

    /// 爱下小说 / 爱下电子: single-quoted keys plus a single-quoted JSON body.
    func testParseSingleQuotedOptionsWithNestedJSONBody() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api,{'method': 'POST','body': '{"searchTerms":"剑来","pageSize": "20"}'}"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/api")
        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(
            String(data: directive.body ?? Data(), encoding: .utf8),
            #"{"searchTerms":"剑来","pageSize": "20"}"#
        )
    }

    /// 零点看书 / 全本小说: `{...};` followed by more JavaScript.
    func testParseOptionsFollowedByTrailingScript() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api,{"method":"POST","body":"q=1"}; var x = 1; @js:result"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/api")
        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "q=1")
    }

    /// 大米小说: the charset value closes with a mismatched double quote.
    func testParseOptionsWithMismatchedCharsetQuote() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api,{'charset': 'UTF-8"','method': 'POST','body': 'a=1'}"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/api")
        XCTAssertEqual(directive.expectedCharset, "UTF-8")
        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "a=1")
    }

    /// 酷我音乐: a backtick and template value trail the object.
    func testParseOptionsWithTrailingBacktickAndTemplateValue() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api,{"type":"${type}"}`"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/api")
        XCTAssertEqual(directive.responseType, "${type}")
    }

    /// A JS rule may contain `,{}`; it must not be cut into a URL + options.
    func testJavaScriptRuleWithObjectArgumentIsNotSplit() {
        let rule = #"@js:java.connect(su,{}).headers('Location')"#
        let directive = SourceURLDirectiveParser().parse(rule)

        XCTAssertEqual(directive.urlText, rule)
        XCTAssertNil(directive.body)
        XCTAssertEqual(directive.method, .get)
    }

    /// Only the first balanced object is the option block.
    func testParseOptionsIgnoresFollowingObject() {
        let directive = SourceURLDirectiveParser().parse(
            #"https://example.com/api,{"method":"POST","body":"a=1"},{"unrelated":true}"#
        )

        XCTAssertEqual(directive.urlText, "https://example.com/api")
        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(String(data: directive.body ?? Data(), encoding: .utf8), "a=1")
    }

    // `URL(string:)` percent-encodes the braces of an inline option object, so a
    // resolved `tocUrl` template arrives as `...,%7B%22body%22...`.  Dropping the
    // options turned the POST into a GET on `/catalog,%7B...` (爱下电子, 30s
    // WebView timeout in the 1.0.93 LAN run).
    func testParsePercentEncodedJSONOptionsAfterURLNormalization() {
        let directive = SourceURLDirectiveParser().parse(
            "https://apiv2hans.aixdzs.com/catalog,%7B%0A%20%20%22body%22:%20%27%7B%22bookId%22:%22383523%22%7D%27,%0A%20%20%22method%22:%20%22POST%22%0A%7D"
        )

        XCTAssertEqual(directive.urlText, "https://apiv2hans.aixdzs.com/catalog")
        XCTAssertEqual(directive.method, .post)
        XCTAssertEqual(
            String(data: directive.body ?? Data(), encoding: .utf8),
            "{\"bookId\":\"383523\"}"
        )
    }
}
