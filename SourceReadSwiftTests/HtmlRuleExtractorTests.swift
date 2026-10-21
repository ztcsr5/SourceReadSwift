import XCTest
import SwiftSoup
@testable import SourceReadSwift

final class HtmlRuleExtractorTests: XCTestCase {
    func testValueUsesFirstNonEmptyAlternative() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="book"><a class="title" href="/book/1">Title</a></div>
        </body></html>
        """)

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: ".missing@href || .book .title@text",
            baseUrl: URL(string: "https://example.com/search")!
        )

        XCTAssertEqual(value, "Title")
    }

    func testAlternativeURLAttributeIsAbsolutized() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="book"><a class="title" href="/book/1">Title</a></div>
        </body></html>
        """)

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: ".missing@href || .book .title@href",
            baseUrl: URL(string: "https://example.com/search")!
        )

        XCTAssertEqual(value, "https://example.com/book/1")
    }

    func testPutAndGetDirectivesPersistAcrossExtractorInstances() throws {
        let document = try SwiftSoup.parse("""
        <html><body><span class="host">https://example.com</span></body></html>
        """)
        let state = RulePersistentState()
        let baseURL = URL(string: "https://example.com/search")!

        let first = HtmlRuleExtractor(executionContext: RuleExecutionContext(persistentState: state))
        _ = try first.value(from: document, rule: "@put:{host:.host@text}span@text", baseUrl: baseURL)

        let second = HtmlRuleExtractor(executionContext: RuleExecutionContext(persistentState: state))
        let value = try second.value(from: document, rule: "@get:{host}/book/1", baseUrl: baseURL)

        XCTAssertEqual(value, "https://example.com/book/1")
    }

    func testRegexTransformCleansExtractedValue() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="book"><a class="title">[完结] Title 最新章节</a></div>
        </body></html>
        """)

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: ".book .title@text##\\[完结\\] | 最新章节##",
            baseUrl: URL(string: "https://example.com/search")!
        )

        XCTAssertEqual(value, "Title")
    }

    func testIndexedSelectorPicksRequestedElement() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <a class="chapter" href="/c/1">One</a>
          <a class="chapter" href="/c/2">Two</a>
        </body></html>
        """)

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: ".chapter@1@href",
            baseUrl: URL(string: "https://example.com/book")!
        )

        XCTAssertEqual(value, "https://example.com/c/2")
    }

    func testOwnTextAndTextNodesAreSupported() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="intro">Outer <span>Inner</span> Tail</div>
        </body></html>
        """)

        let ownText = try HtmlRuleExtractor().value(
            from: document,
            rule: ".intro@ownText",
            baseUrl: URL(string: "https://example.com")!
        )
        let textNodes = try HtmlRuleExtractor().value(
            from: document,
            rule: ".intro@textNodes",
            baseUrl: URL(string: "https://example.com")!
        )

        XCTAssertEqual(ownText, "Outer Tail")
        XCTAssertTrue(textNodes.contains("Outer"))
        XCTAssertTrue(textNodes.contains("Tail"))
    }

    func testAllAttributeJoinsMultipleElements() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <p>A</p>
          <p>B</p>
        </body></html>
        """)

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: "p@all",
            baseUrl: URL(string: "https://example.com")!
        )

        XCTAssertEqual(value, "A\nB")
    }

    func testMergeOperatorInterleavesHTMLValues() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <a class="free" href="/1">第一章</a>
          <a class="free" href="/3">第三章</a>
          <a class="vip" href="/2">第二章</a>
          <a class="vip" href="/4">第四章</a>
        </body></html>
        """)

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: ".free@text%%.vip@text",
            baseUrl: URL(string: "https://example.com")!
        )

        XCTAssertEqual(value, "第一章\n第二章\n第三章\n第四章")
    }

    func testMergeOperatorInterleavesHTMLNodes() throws {
        let html = """
        <html><body>
          <a class="free" href="/1">第一章</a>
          <a class="free" href="/3">第三章</a>
          <a class="vip" href="/2">第二章</a>
          <a class="vip" href="/4">第四章</a>
        </body></html>
        """

        let elements = try HtmlRuleExtractor().select(
            html,
            baseUrl: URL(string: "https://example.com")!,
            listRule: ".free%%.vip"
        )

        XCTAssertEqual(try elements.map { try $0.text() }, ["第一章", "第二章", "第三章", "第四章"])
    }

    func testStringListPreservesNodeBoundariesAndInnerNewlines() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="c">A<span>X</span>B</div>
          <div class="c">C</div>
        </body></html>
        """)

        let extractor = HtmlRuleExtractor()

        // Legado `getStringList` adds one element per selected node.  A
        // `@textNodes` value that already contains newlines stays a single
        // element instead of being split into two.
        XCTAssertEqual(
            try extractor.stringList(from: document, rule: ".c@textNodes"),
            ["A\nB", "C"]
        )
        XCTAssertEqual(
            try extractor.value(from: document, rule: ".c@textNodes"),
            "A\nB\nC"
        )
        XCTAssertEqual(
            try extractor.stringList(from: document, rule: ".missing||.c@textNodes"),
            ["A\nB", "C"]
        )
        XCTAssertEqual(
            try extractor.stringList(from: document, rule: ".c@textNodes%%.c@textNodes"),
            ["A\nB", "A\nB", "C", "C"]
        )
    }
    func testListFallbackUsesFirstNonEmptySelector() throws {
        let html = """
        <html><body>
          <a class="book">Book</a>
        </body></html>
        """

        let elements = try HtmlRuleExtractor().select(
            html,
            baseUrl: URL(string: "https://example.com")!,
            listRule: ".missing || .book"
        )

        XCTAssertEqual(try elements.map { try $0.text() }, ["Book"])
    }

    func testFallbackOperatorIgnoresNestedCSSOperatorText() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <a data-key="Alpha || Beta">Primary</a>
          <span>Fallback</span>
        </body></html>
        """)

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: "a[data-key='Alpha || Beta']@text || span@text",
            baseUrl: URL(string: "https://example.com")!
        )

        XCTAssertEqual(value, "Primary")
    }

    func testXPathTextRuleJoinsMultipleValues() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div id="content">
            <p>Line A</p>
            <p>Line B</p>
          </div>
        </body></html>
        """)

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: #"//div[@id="content"]/p/text()"#,
            baseUrl: URL(string: "https://example.com")!
        )

        XCTAssertEqual(value, "Line A\nLine B")
    }

    func testXPathAttributeAndTextRulesInterleave() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="toc">
            <a href="/1">Chapter 1</a>
            <a href="/2">Chapter 2</a>
          </div>
        </body></html>
        """)

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: #"//div[@class="toc"]/a/@href%%//div[@class="toc"]/a/text()"#,
            baseUrl: URL(string: "https://example.com/book")!
        )

        XCTAssertEqual(value, "https://example.com/1\nChapter 1\nhttps://example.com/2\nChapter 2")
    }

    func testXPathPrefixAndCSSPrefixAreNormalized() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="book"><a href="/book/1">Book One</a></div>
        </body></html>
        """)

        let xpath = try HtmlRuleExtractor().value(
            from: document,
            rule: #"@XPath://div[@class="book"]/a/text()"#,
            baseUrl: URL(string: "https://example.com")!
        )
        let css = try HtmlRuleExtractor().value(
            from: document,
            rule: "@CSS:.book a@href",
            baseUrl: URL(string: "https://example.com")!
        )

        XCTAssertEqual(xpath, "Book One")
        XCTAssertEqual(css, "https://example.com/book/1")
    }

    func testXPathSelectorSupportsAttributeFiltersAndIndexes() throws {
        let html = """
        <html><body>
          <ul>
            <li data-id="1"><a href="/a">A</a></li>
            <li data-id="2"><a href="/b">B</a></li>
          </ul>
        </body></html>
        """

        let first = try HtmlRuleExtractor().select(
            html,
            baseUrl: URL(string: "https://example.com")!,
            listRule: #"//li[@data-id="2"]/a"#
        )
        let last = try HtmlRuleExtractor().select(
            html,
            baseUrl: URL(string: "https://example.com")!,
            listRule: "//li[last()]"
        )

        XCTAssertEqual(try first.map { try $0.text() }, ["B"])
        XCTAssertEqual(try last.map { try $0.text() }, ["B"])
    }

    func testPutAndGetDirectivesShareValuesAcrossRules() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="book">
            <span class="host">https://example.com</span>
            <a class="path" href="/book/1">Title</a>
          </div>
        </body></html>
        """)
        let extractor = HtmlRuleExtractor()

        _ = try extractor.value(
            from: document,
            rule: "@put:{host:.host@text}.book@text",
            baseUrl: URL(string: "https://example.com/search")!
        )
        let value = try extractor.value(
            from: document,
            rule: "@get:{host}/book/1",
            baseUrl: URL(string: "https://example.com/search")!
        )

        XCTAssertEqual(value, "https://example.com/book/1")
    }
    func testPutDirectiveSplitsQuotedCommaAndColonSafely() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <span class="url">https://example.com/a,b:c</span>
        </body></html>
        """)
        let extractor = HtmlRuleExtractor()

        _ = try extractor.value(
            from: document,
            rule: #"@put:{"base":".url@text"}span@text"#,
            baseUrl: URL(string: "https://example.com")!
        )
        let value = try extractor.value(
            from: document,
            rule: "@get:{base}",
            baseUrl: URL(string: "https://example.com")!
        )

        XCTAssertEqual(value, "https://example.com/a,b:c")
    }

    func testHtmlRuleExtractorElementJavaScriptRuleWithParentNodeAndSelect() throws {
        let html = """
        <div class="volume">
          <h2>第一卷 异界</h2>
          <div class="nested">
            <div class="chapter"><a href="/c1.html">第1章 降临</a></div>
          </div>
        </div>
        """
        let doc = try SwiftSoup.parse(html)
        let chapterEl = try doc.select(".chapter").first()!
        let extractor = HtmlRuleExtractor()

        let scriptRule = "@js:\nvar title = result.parentNode().parentNode();\nresult = title.select('h2').text() + ' ' + result.text()"
        let value = try extractor.value(
            from: chapterEl,
            rule: scriptRule,
            baseUrl: URL(string: "https://example.com/book/1")!
        )

        XCTAssertEqual(value, "第一卷 异界 第1章 降临")
    }

    func testSameRulePutAndGetReturnsDirectiveValue() throws {
        let document = try SwiftSoup.parse("""
        <html><body><span class="host">https://example.com</span></body></html>
        """)
        let extractor = HtmlRuleExtractor()

        let value = try extractor.value(
            from: document,
            rule: "@put:{host:.host@text}@get:{host}",
            baseUrl: URL(string: "https://example.com/search")!
        )

        XCTAssertEqual(value, "https://example.com")
    }

    func testSameRulePutAndGetWithLiteralSuffix() throws {
        let document = try SwiftSoup.parse("""
        <html><body><span class="host">https://example.com</span></body></html>
        """)
        let extractor = HtmlRuleExtractor()

        let value = try extractor.value(
            from: document,
            rule: "@put:{host:.host@text}@get:{host}/book/1",
            baseUrl: URL(string: "https://example.com/search")!
        )

        XCTAssertEqual(value, "https://example.com/book/1")
    }

    func testDirectGetAppliesRegexTransformToStoredValue() throws {
        let document = try SwiftSoup.parse("""
        <html><body><span class="host">https://example.com</span></body></html>
        """)
        let extractor = HtmlRuleExtractor()

        _ = try extractor.value(
            from: document,
            rule: "@put:{host:.host@text}.host@text",
            baseUrl: URL(string: "https://example.com/search")!
        )
        let value = try extractor.value(
            from: document,
            rule: #"@get:{host}##^https://##http://"#,
            baseUrl: URL(string: "https://example.com/search")!
        )

        XCTAssertEqual(value, "http://example.com")

        // Legado's four-field form (`##pattern##replacement###`) returns
        // `matcher.group(0).replaceFirst(...)`: only the first match with the
        // replacement applied, not the whole input string.
        let firstMatch = try extractor.value(
            from: document,
            rule: #"@get:{host}##^https://(.*)$##$1###"#,
            baseUrl: URL(string: "https://example.com/search")!
        )
        XCTAssertEqual(firstMatch, "example.com")
    }

    func testDirectGetSupportsBareKeyWithLiteralSuffix() throws {
        let document = try SwiftSoup.parse("""
        <html><body><span class="host">https://example.com</span></body></html>
        """)
        let extractor = HtmlRuleExtractor()

        _ = try extractor.value(
            from: document,
            rule: "@put:{host:.host@text}.host@text",
            baseUrl: URL(string: "https://example.com/search")!
        )
        let value = try extractor.value(
            from: document,
            rule: "@get:host/book/1",
            baseUrl: URL(string: "https://example.com/search")!
        )

        XCTAssertEqual(value, "https://example.com/book/1")
    }

    // MARK: - Legado operator precedence and cross-dialect state

    func testStringListConcatenatesAmpersandBranches() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="a">A</div>
          <div class="b">B</div>
        </body></html>
        """)

        let values = try HtmlRuleExtractor().stringList(
            from: document,
            rule: ".a@text&&.b@text",
            baseUrl: nil
        )

        XCTAssertEqual(values, ["A", "B"])
    }

    func testSelectConcatenatesAmpersandBranches() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="a">A</div>
          <div class="b">B</div>
        </body></html>
        """)

        let elements = try HtmlRuleExtractor().select(
            from: document,
            rule: ".a&&.b",
            baseUrl: nil
        )

        XCTAssertEqual(try elements.map { try $0.text() }, ["A", "B"])
    }

    func testAmpersandAndAlternativeOperatorsUseSourceOrder() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="a">A</div>
          <div class="b">B</div>
        </body></html>
        """)

        // `&&` appears first, so the rule is `(.missing && (.a || .b))`.
        // Splitting on `||` first would incorrectly return only `B`.
        let values = try HtmlRuleExtractor().stringList(
            from: document,
            rule: ".missing@text&&.a@text||.b@text",
            baseUrl: nil
        )

        XCTAssertEqual(values, ["A"])
    }

    func testPutDirectiveValueRuleSeesVariables() throws {
        let document = try SwiftSoup.parse("""
        <html><body><span class="x">X</span></body></html>
        """)
        let extractor = HtmlRuleExtractor()

        _ = try extractor.value(
            from: document,
            rule: "@put:{token:@js:keyword}.x@text",
            baseUrl: nil,
            variables: ["keyword": "abc123"]
        )
        let value = try extractor.value(
            from: document,
            rule: "@get:{token}",
            baseUrl: nil
        )

        XCTAssertEqual(value, "abc123")
    }

    func testHtmlPutIsVisibleToNestedJsonGet() throws {
        let document = try SwiftSoup.parse("""
        <html><body><span class="host">https://example.com</span></body></html>
        """)
        let context = RuleExecutionContext()
        let html = HtmlRuleExtractor(executionContext: context)

        _ = try html.value(
            from: document,
            rule: "@put:{host:.host@text}.host@text",
            baseUrl: nil
        )

        let json = JSONRuleExtractor(executionContext: context)
        let value = json.value(from: ["ok": true], path: "@get:{host}")

        XCTAssertEqual(value as? String, "https://example.com")
    }

    func testJsonPutIsVisibleToHtmlGet() throws {
        let context = RuleExecutionContext()
        let json = JSONRuleExtractor(executionContext: context)

        _ = json.value(
            from: ["host": "https://example.com"],
            path: "@put:{host:$.host}$.host"
        )

        let document = try SwiftSoup.parse("<html><body></body></html>")
        let html = HtmlRuleExtractor(executionContext: context)
        let value = try html.value(
            from: document,
            rule: "@get:{host}",
            baseUrl: nil
        )

        XCTAssertEqual(value, "https://example.com")
    }

    func testSelectJavaScriptRuleSeesExternalVariables() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="item">A</div>
          <div class="item">B</div>
        </body></html>
        """)
        let extractor = HtmlRuleExtractor()

        let elements = try extractor.select(
            from: document,
            rule: "@js:result = result.select('.' + keyword)",
            baseUrl: nil,
            variables: ["keyword": "item"]
        )

        XCTAssertEqual(elements.count, 2)
    }

    func testAngleJavaScriptSelectRuleSeesExternalVariables() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="item">A</div>
          <div class="item">B</div>
        </body></html>
        """)
        let extractor = HtmlRuleExtractor()

        let elements = try extractor.select(
            from: document,
            rule: "<js>result = result.select('.' + keyword).eq(page - 1)</js>",
            baseUrl: nil,
            variables: ["keyword": "item", "page": 2]
        )

        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(try elements.first?.text(), "B")
    }

    func testElementJavaScriptSelectKeepsLiveParentChain() throws {
        let document = try SwiftSoup.parse("""
        <html><body><div class="wrap"><span class="item">A</span></div></body></html>
        """)
        let extractor = HtmlRuleExtractor()

        let elements = try extractor.select(
            from: document,
            rule: "@js:result = result.select('.item').first().parent()",
            baseUrl: nil
        )

        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(try elements.first?.tagName(), "div")
        XCTAssertEqual(try elements.first?.hasClass("wrap"), true)
    }
    func testSelectJavaScriptRuleResolvesGetDirectiveTemplate() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="item">A</div>
          <div class="item">B</div>
          <span class="cls">item</span>
        </body></html>
        """)
        let extractor = HtmlRuleExtractor()
        _ = try extractor.value(from: document, rule: "@put:{cls:.cls@text}.cls@text", baseUrl: nil)

        let elements = try extractor.select(
            from: document,
            rule: "@js:result = result.select('.' + '@get:{cls}')",
            baseUrl: nil
        )

        XCTAssertEqual(elements.count, 2)
    }

    func testSelectJavaScriptRuleSeesStoredPutValueAsBareVariable() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="item">A</div>
          <div class="item">B</div>
          <span class="cls">item</span>
        </body></html>
        """)
        let extractor = HtmlRuleExtractor()
        _ = try extractor.value(from: document, rule: "@put:{cls:.cls@text}.cls@text", baseUrl: nil)

        let elements = try extractor.select(
            from: document,
            rule: "@js:result = result.select('.' + cls)",
            baseUrl: nil
        )

        XCTAssertEqual(elements.count, 2)
    }

    func testJavaScriptValueRuleSeesStoredPutValueAsBareVariable() throws {
        let document = try SwiftSoup.parse("""
        <html><body><span class="token">abc123</span></body></html>
        """)
        let extractor = HtmlRuleExtractor()
        _ = try extractor.value(from: document, rule: "@put:{token:.token@text}.token@text", baseUrl: nil)

        let value = try extractor.value(
            from: document,
            rule: "@js:return token.toUpperCase()",
            baseUrl: nil
        )

        XCTAssertEqual(value, "ABC123")
    }
}
