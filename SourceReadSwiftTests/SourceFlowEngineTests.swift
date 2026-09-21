import XCTest
import Foundation
import SwiftSoup
@testable import SourceReadSwift

final class SourceFlowEngineTests: XCTestCase {
    
    // MARK: - Category 1: Dynamic JavaScript URL Resolution
    func testDynamicURLResolverWithSimpleJS() {
        let rawUrl = "@js:'https://api.example.com/books/' + (100 + 23)"
        let source = BookSource(bookSourceName: "DynamicTest", bookSourceUrl: "https://example.com")
        let context = RuleExecutionContext()
        let resolved = DynamicURLResolver.resolve(
            rawUrl,
            baseUrl: "https://example.com",
            source: source,
            context: context
        )
        XCTAssertEqual(resolved, "https://api.example.com/books/123")
    }
    
    func testDynamicURLResolverPreservesNormalURL() {
        let rawUrl = "/api/v1/search?keyword=test"
        let source = BookSource(bookSourceName: "NormalTest", bookSourceUrl: "https://example.com")
        let context = RuleExecutionContext()
        let resolved = DynamicURLResolver.resolve(
            rawUrl,
            baseUrl: "https://example.com",
            source: source,
            context: context
        )
        XCTAssertEqual(resolved, rawUrl)
    }

    // MARK: - Category 2: 4-Stage Composite Pipeline & Template Interpolation
    func testHtmlExtractorTemplateInterpolationWithCSS() throws {
        let html = """
        <html><body>
          <div class="meta">
            <span class="author">鲁迅</span>
            <span class="category">文学</span>
          </div>
        </body></html>
        """
        let doc = try SwiftSoup.parse(html)
        let extractor = HtmlRuleExtractor()
        
        let templateRule = "作者: {{@css:.author@text}} | 分类: {{@css:.category@text}}"
        let result = try extractor.value(from: doc, rule: templateRule, baseUrl: URL(string: "https://example.com")!)
        XCTAssertEqual(result, "作者: 鲁迅 | 分类: 文学")
    }
    
    func testHtmlExtractorEvaluateJSWithTrailingRegex() throws {
        let doc = try SwiftSoup.parse("<div><span class='title'>第1章 开始</span></div>")
        let extractor = HtmlRuleExtractor()
        
        // Rule with JS and trailing regex ##
        let rule = "@js: '第1章 开始' ##(第\\d+章)##【$1】"
        let result = try extractor.value(from: doc, rule: rule, baseUrl: URL(string: "https://example.com")!)
        XCTAssertEqual(result, "【第1章】 开始")
    }
    
    // MARK: - Category 3: JavaScriptCore Runtime Extension & Java Bridges
    func testJSCoreRuntimeExtensions() {
        let rt = JSCoreRuntime()
        
        // Test TYPE
        let typeResult = try? rt.evaluate("TYPE('hello')").get()
        XCTAssertEqual(typeResult, "string")
        
        // Test ruid
        let ruidResult = try? rt.evaluate("var r = ruid(); typeof r === 'string' && r.length === 16").get()
        XCTAssertEqual(ruidResult, "true")
        
        // Test source.getKey & setKey
        _ = try? rt.evaluate("source.setKey('session_token', 'token_xyz_999')").get()
        let getKeyResult = try? rt.evaluate("source.getKey('session_token')").get()
        XCTAssertEqual(getKeyResult, "token_xyz_999")
        
        // Test HMacHex & HMacBase64
        let hmacHex = try? rt.evaluate("HMacHex('HmacSHA256', 'secret', 'message')").get()
        XCTAssertNotNil(hmacHex)
        XCTAssertFalse((hmacHex ?? "").isEmpty)
        
        // Test toNumChapter
        let numChapter = try? rt.evaluate("toNumChapter('第一千二百三十四章')").get()
        XCTAssertNotNil(numChapter)
        XCTAssertTrue((numChapter ?? "").contains("1234"))
    }
    
    func testSimplifiedTraditionalChineseConversion() {
        let rt = JSCoreRuntime()
        
        // Test s2t (Simplified to Traditional)
        let trad = try? rt.evaluate("s2t('中国科技发展')").get()
        XCTAssertNotNil(trad)
        XCTAssertTrue((trad ?? "").contains("國") || (trad ?? "").contains("發") || !(trad ?? "").isEmpty)
        
        // Test t2s (Traditional to Simplified)
        let simp = try? rt.evaluate("t2s('中華民國')").get()
        XCTAssertNotNil(simp)
        XCTAssertTrue((simp ?? "").contains("华") || (simp ?? "").contains("国") || !(simp ?? "").isEmpty)
    }

    // MARK: - Category 5: GBK Character Set Detection
    func testGBKCharsetDetection() {
        let defaultSource = BookSource(bookSourceName: "默认源", bookSourceUrl: "https://example.com")
        XCTAssertFalse(SearchURLResolver.isGBKEncoding(searchUrl: "https://example.com/search", source: defaultSource))
        
        let gbkSource = BookSource(bookSourceName: "GBK源", bookSourceUrl: "https://example.com", raw: ["charset": "gbk"])
        XCTAssertTrue(SearchURLResolver.isGBKEncoding(searchUrl: "https://example.com/search", source: gbkSource))
        
        let gb2312Source = BookSource(bookSourceName: "GB2312源", bookSourceUrl: "https://example.com", raw: ["charset": "gb2312"])
        XCTAssertTrue(SearchURLResolver.isGBKEncoding(searchUrl: "https://example.com/search", source: gb2312Source))
    }
    
    // MARK: - Category 6: Anti-Bot & Turing Diagnostics Classification
    func testAntiBotDiagnosticClassification() {
        let step = SourceDiagnosticStep(
            stage: .search,
            status: .verificationRequired,
            responseSummary: "触发 bdturing 图灵滑块安全验证",
            failureClassification: "anti_bot.turing",
            responseStatusCode: 403
        )
        let report = SourceDiagnosticReport(
            sourceName: "番茄测试源",
            sourceURL: "https://fanqie.example.com",
            keyword: "剑来",
            startedAt: Date(),
            steps: [step]
        )
        let classification = SourceDiagnosticReportExporter.classify(report: report)
        XCTAssertEqual(classification.category, .antiBotShield)
    }

    // MARK: - Chained <js> Rules & URL Safety
    func testChainedJSToJSONRule() {
        let rule = "<js>var list = {'turl': 'https://example.com/chapters'}; JSON.stringify(list)</js>$.turl"
        let source = BookSource(bookSourceName: "测试源", bookSourceUrl: "https://example.com")
        let context = RuleExecutionContext()
        let resolved = DynamicURLResolver.resolve(rule, baseUrl: "https://example.com", source: source, context: context)
        XCTAssertEqual(resolved, "https://example.com/chapters")
    }

    func testChainedJSToHtmlRule() throws {
        let extractor = HtmlRuleExtractor(executionContext: RuleExecutionContext())
        let doc = try SwiftSoup.parse("<div>initial</div>", "https://example.com")
        let rule = "<js>'<div class=\"news_details\"><li>唐家三少</li></div>'</js>class.news_details@tag.li.0@text"
        let result = try extractor.value(from: doc, rule: rule, fallback: nil, baseUrl: URL(string: "https://example.com"))
        XCTAssertEqual(result, "唐家三少")
    }

    func testJSCoreRuntimeGlobalDollarAndSourceKey() {
        let rt = JSCoreRuntime()
        // Test $ global variable
        let evalDollar = try? rt.evaluate("typeof $").get()
        XCTAssertEqual(evalDollar, "function")

        // Test iid global variable
        let evalIid = try? rt.evaluate("typeof iid").get()
        XCTAssertEqual(evalIid, "string")

        // Test source.getKey() retains raw fragment
        let source = BookSource(bookSourceName: "玄幻文学", bookSourceUrl: "https://m.xhwx6.com#")
        let evalKey = try? rt.evaluate("source.getKey()", variables: ["source": source]).get()
        XCTAssertEqual(evalKey, "https://m.xhwx6.com#")
    }

    func testDiscardJavascriptAndAnchorUrls() {
        let extractor = HtmlRuleExtractor(executionContext: RuleExecutionContext())
        guard let base = URL(string: "http://dict.cn") else { return }
        XCTAssertEqual(extractor.absolutize("javascript:void(0);", base: base), "")
        XCTAssertEqual(extractor.absolutize("javascript:;", base: base), "")
        XCTAssertEqual(extractor.absolutize("#", base: base), "")
    }

    // MARK: - Byte-Level Comma Sanitizer & Fast-Path Import
    func testByteLevelSanitizeTrailingCommas() {
        let malformedJSON = "{\"items\": [{\"name\": \"test1\", }, {\"name\": \"test2\",}, ], \"count\": 2, }"
        let sanitized = SourceStore.sanitizeTrailingCommas(malformedJSON)
        XCTAssertFalse(sanitized.contains(", }"))
        XCTAssertFalse(sanitized.contains(",}"))
        XCTAssertFalse(sanitized.contains(", ]"))

        let parsed = try? JSONSerialization.jsonObject(with: Data(sanitized.utf8)) as? [String: Any]
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?["count"] as? Int, 2)
    }

    @MainActor
    func testFastPathBookSourceImport() throws {
        let store = SourceStore()
        let json = """
        [
            {
                "bookSourceName": "极速源1",
                "bookSourceUrl": "https://fast1.example.com",
                "searchUrl": "https://fast1.example.com/search?k={{key}}"
            },
            {
                "bookSourceName": "极速源2",
                "bookSourceUrl": "https://fast2.example.com",
                "searchUrl": "https://fast2.example.com/search?k={{key}}"
            }
        ]
        """
        let report = try store.importJSON(json)
        XCTAssertGreaterThanOrEqual(report.totalAdded + report.totalUpdated, 2)
        XCTAssertNotNil(store.source(for: "https://fast1.example.com"))
        XCTAssertNotNil(store.source(for: "https://fast2.example.com"))
    }

    // MARK: - Hash Fragment Preservation in Source Variables
    func testSourceVariableMapPreservesHashFragment() {
        let sourceWithHash = BookSource(
            bookSourceName: "爱下小说（优）",
            bookSourceUrl: "https://apiv2hans.aixdzs.com##@secret123",
            searchUrl: "https://apiv2hans.aixdzs.com/search"
        )
        let rt = JSCoreRuntime()
        let result = try? rt.evaluate("source.getKey()", variables: ["source": sourceWithHash]).get()
        XCTAssertEqual(result, "https://apiv2hans.aixdzs.com##@secret123")
    }

    // MARK: - Deep Diagnostic Sniffing (WAF, 5s Shield, API Errors)
    func testSniffSnippetRegionalWAF() {
        let wafHTML = "<!DOCTYPE html><html><head><title>地区拦截</title></head><body>WAF Blocked</body></html>"
        let sniffed = SourceDiagnosticClassifier.sniffSnippet(snippet: wafHTML, statusCode: 403, stage: "search")
        XCTAssertNotNil(sniffed)
        XCTAssertEqual(sniffed?.kind, .blocked)
        XCTAssertEqual(sniffed?.status, .blocked)
        XCTAssertTrue(sniffed?.classification.contains("地区拦截") == true)
    }

    func testSniffSnippetCloudflareShield() {
        let cfHTML = "<!DOCTYPE html><html><head><title>Just a moment...</title></head><body>cf-chl-bypass</body></html>"
        let sniffed = SourceDiagnosticClassifier.sniffSnippet(snippet: cfHTML, statusCode: 403, stage: "search")
        XCTAssertNotNil(sniffed)
        XCTAssertEqual(sniffed?.kind, .blocked)
        XCTAssertTrue(sniffed?.classification.contains("5秒盾") == true)
    }

    func testSniffSnippetAPIBusinessError() {
        let apiJSON = "{\"code\":\"1055\",\"message\":\"1055:没有该小说呢！\",\"data\":{}}"
        let sniffed = SourceDiagnosticClassifier.sniffSnippet(snippet: apiJSON, statusCode: 200, stage: "search")
        XCTAssertNotNil(sniffed)
        XCTAssertEqual(sniffed?.kind, .emptyResult)
        XCTAssertEqual(sniffed?.status, .warning)
        XCTAssertTrue(sniffed?.summary.contains("没有该小说呢！") == true)
    }

    func testSniffSnippetEmptyStream() {
        let sniffed = SourceDiagnosticClassifier.sniffSnippet(snippet: "", statusCode: 200, decodedByteCount: 19, stage: "search")
        XCTAssertNotNil(sniffed)
        XCTAssertEqual(sniffed?.kind, .emptyResult)
        XCTAssertTrue(sniffed?.summary.contains("19 字节") == true)
    }

    // MARK: - Background KeepAlive Manager
    @MainActor
    func testBackgroundKeepAliveManagerLifecycle() {
        let manager = BackgroundKeepAliveManager.shared
        manager.start(reason: "UnitTest")
        XCTAssertTrue(manager.isActive)
        manager.stop()
        XCTAssertFalse(manager.isActive)
    }
}

