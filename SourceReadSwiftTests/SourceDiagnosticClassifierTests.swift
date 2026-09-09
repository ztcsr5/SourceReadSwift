import XCTest
@testable import SourceReadSwift

final class SourceDiagnosticClassifierTests: XCTestCase {
    func testClassifiesVerificationAndLoginBeforeGenericFailure() {
        XCTAssertEqual(SourceDiagnosticClassifier.status(message: "Cloudflare challenge", stage: "search"), .verificationRequired)
        XCTAssertEqual(SourceDiagnosticClassifier.status(message: "HTTP 401 unauthorized", stage: "search"), .requiresLogin)
    }

    func testClassifiesBlockedAndEmptyResults() {
        XCTAssertEqual(SourceDiagnosticClassifier.status(message: "HTTP 403 Forbidden", stage: "search"), .blocked)
        XCTAssertEqual(SourceDiagnosticClassifier.status(message: "搜索结果为空", stage: "search", resultCount: 0), .warning)
    }

    func testProvidesStableFailureKindsAndRetryPolicy() {
        XCTAssertEqual(SourceDiagnosticClassifier.kind(message: "HTTP 429 rate limit", stage: "search"), .blocked)
        XCTAssertEqual(SourceDiagnosticClassifier.kind(message: "搜索超时", stage: "search"), .timeout)
        XCTAssertEqual(SourceDiagnosticClassifier.kind(error: .rule("JSONPath 解析失败"), stage: "content"), .parsing)
        XCTAssertEqual(SourceDiagnosticClassifier.kind(error: .javascript("脚本异常"), stage: "search"), .javascript)
        XCTAssertTrue(SourceDiagnosticFailureKind.timeout.isRetryable)
        XCTAssertFalse(SourceDiagnosticFailureKind.parsing.isRetryable)
    }

    func testLegacyDiagnosticStepDefaultsFailureKindToNil() throws {
        let data = Data(#"{"stage":"search","status":"failed","matchCount":0}"#.utf8)
        let step = try JSONDecoder().decode(SourceDiagnosticStep.self, from: data)
        XCTAssertNil(step.failureCode)
        XCTAssertFalse(step.retryable)
    }

    func testClassifiesCLevelFailureTaxonomy() {
        // Verification / CAPTCHA / CF
        XCTAssertEqual(SourceDiagnosticClassifier.kind(message: "请输入验证码：", stage: "search"), .verification)
        XCTAssertEqual(SourceDiagnosticClassifier.kind(error: .javascript("getVerificationCode failed"), stage: "content"), .verification)
        XCTAssertEqual(SourceDiagnosticClassifier.status(message: "触发人机验证 actyzm", stage: "search"), .verificationRequired)

        // GBK / Charset
        XCTAssertEqual(SourceDiagnosticClassifier.kind(message: "GBK 编码解析失败", stage: "search"), .parsing)
        XCTAssertEqual(SourceDiagnosticClassifier.kind(error: .rule("不支持 gb2312 编码"), stage: "toc"), .parsing)

        // AES / Crypto / Base64
        XCTAssertEqual(SourceDiagnosticClassifier.kind(message: "AES decrypt failed", stage: "content"), .javascript)
        XCTAssertEqual(SourceDiagnosticClassifier.kind(error: .javascript("createSymmetricCrypto error"), stage: "content"), .javascript)
        XCTAssertEqual(SourceDiagnosticClassifier.kind(message: "段落乱序恢复异常", stage: "content"), .javascript)

        // Font obfuscation
        XCTAssertEqual(SourceDiagnosticClassifier.kind(message: "queryTTF 字体反爬解析错误", stage: "content"), .parsing)
    }
}
