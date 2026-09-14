import XCTest
import Foundation
import SwiftSoup
@testable import SourceReadSwift

final class SourceFlowEngineTests: XCTestCase {
    
    // MARK: - Category 1: Dynamic JavaScript URL Resolution
    func testDynamicURLResolverWithSimpleJS() {
        let rawUrl = "@js:'https://api.example.com/books/' + (100 + 23)"
        let resolved = DynamicURLResolver.resolve(
            urlString: rawUrl,
            baseUrl: URL(string: "https://example.com")!,
            evaluator: { script in
                let rt = JSCoreRuntime()
                return try? rt.evaluate(script).get()
            }
        )
        XCTAssertEqual(resolved, "https://api.example.com/books/123")
    }
    
    func testDynamicURLResolverPreservesNormalURL() {
        let rawUrl = "/api/v1/search?keyword=test"
        let resolved = DynamicURLResolver.resolve(
            urlString: rawUrl,
            baseUrl: URL(string: "https://example.com")!,
            evaluator: { _ in nil }
        )
        XCTAssertEqual(resolved, "https://example.com/api/v1/search?keyword=test")
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
        var source = BookSource.empty()
        
        // Default utf-8
        XCTAssertFalse(SearchURLResolver.isGBKEncoding(source: source))
        
        // With gbk charset
        source.charset = "gbk"
        XCTAssertTrue(SearchURLResolver.isGBKEncoding(source: source))
        
        source.charset = "gb2312"
        XCTAssertTrue(SearchURLResolver.isGBKEncoding(source: source))
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
}
