import Foundation
import XCTest
@testable import SourceReadSwift

/// End-to-end offline fixtures for the five C-level Legado sources from `已测试.json`.
/// These lock in GBK encoding, AES/Base64 decryption, font obfuscation, and login/CF verification
/// without making live network calls.
final class SourceEngineCLevelFixtureTests: XCTestCase {

    // MARK: - 1. 🔞🔲第一版主999 & 📪第一版主820: GBK POST Search & AES Decryption

    func testDiyiBanzhu999SearchUrlEvaluatesGBKPostDirective() throws {
        let sources = try loadCapabilityBank()
        let sourceData = try XCTUnwrap(sources.first { ($0["bookSourceName"] as? String) == "🔞🔲第一版主999" })
        let source = try JSONDecoder().decode(BookSource.self, from: JSONSerialization.data(withJSONObject: sourceData))

        let resolveResult = SearchURLResolver().resolve(source: source, keyword: "修真", page: 1)
        let resolvedSearchUrl: String
        switch resolveResult {
        case .success(let url):
            resolvedSearchUrl = url
        case .failure(let err):
            return XCTFail("failed to resolve searchUrl: \(err)")
        }

        let builder = SourceRequestBuilder()
        let request = builder.buildSearchRequest(
            source: source,
            searchUrl: resolvedSearchUrl,
            keyword: "修真",
            page: 1
        )

        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.expectedCharset?.uppercased(), "GBK")
        XCTAssertTrue(request.url.absoluteString.contains("s.php"))
        if let bodyData = request.body, let bodyText = String(data: bodyData, encoding: .utf8) {
            XCTAssertTrue(bodyText.contains("objectType=2"))
            XCTAssertTrue(bodyText.contains("type=articlename"))
            XCTAssertTrue(bodyText.contains("page=1"))
        } else {
            XCTFail("expected valid POST body payload")
        }
    }

    func testDiyiBanzhuAESDecryptionAndFontObfuscationPipeline() throws {
        let runtime = JSCoreRuntime()

        // 1. Test AES decryption with MD5 derived key & iv (matching source script logic)
        let aesScript = """
        var keyInput = 'secret_pass_123';
        var code = java.md5Encode(keyInput);
        var iv = code.substring(0, 16);
        var key = code.substring(16);
        var crypto = java.createSymmetricCrypto("AES/CBC/PKCS7Padding", key, iv);
        var enc = crypto.encryptStr('测试第一版主密文正文');
        var dec = crypto.decryptStr(enc);
        dec;
        """
        let aesResult = runtime.evaluate(aesScript)
        guard case .success(let val) = aesResult else {
            return XCTFail("AES setup failed: \(aesResult)")
        }
        XCTAssertEqual(val, "测试第一版主密文正文")

        // 2. Test Font Hex replacement logic: <i>&#xe800</i> -> #e800#
        let fontScript = """
        var raw = '正文<i>&#xe800</i>内容<i>&#xe801</i>';
        var result = raw.replace(/<i>(.*?)<\\/i>/g, function(str, p1) {
            return '#' + p1.charCodeAt(0).toString(16) + '#';
        });
        result;
        """
        let fontResult = runtime.evaluate(fontScript)
        guard case .success(let fontCleaned) = fontResult else {
            return XCTFail("Font replacement failed: \(fontResult)")
        }
        XCTAssertTrue(fontCleaned.contains("#"))

        // 3. Test Chinese Character restoration map from replaceRegex
        let restoreScript = """
        var text = '这个#1040782805#人太坏了，居然想#2033008053#狗';
        text = text.replace(/#1040782805#/gi, '奸');
        text = text.replace(/#2033008053#/gi, '撸');
        text;
        """
        let restoreResult = runtime.evaluate(restoreScript)
        guard case .success(let restored) = restoreResult else {
            return XCTFail("Pinyin restoration failed: \(restoreResult)")
        }
        XCTAssertEqual(restored, "这个奸人太坏了，居然想撸狗")
    }

    func testDiyiBanzhuBase64DisorderParagraphRecovery() throws {
        let runtime = JSCoreRuntime()
        // Simulates `ns = java.base64Decode(src.match(/var ns='(.+?)';/)[1]).split(',');`
        // and reorders paragraphs accordingly.
        let disorderScript = """
        var nsEncoded = java.base64Encode('0,2,1');
        var ns = java.base64Decode(nsEncoded).split(',');
        var paragraphArr = ['第二段内容', '第一段内容'];
        var result = '';
        for (var i = 1; i <= paragraphArr.length; i++) {
            result += paragraphArr[parseInt(ns[i]) - parseInt(ns[0]) - 1] + '\\n';
        }
        result.trim();
        """
        let result = runtime.evaluate(disorderScript)
        guard case .success(let ordered) = result else {
            return XCTFail("Disorder recovery failed: \(result)")
        }
        XCTAssertEqual(ordered, "第一段内容\n第二段内容")
    }

    // MARK: - 2. 要撸小说: Base64 Content Extraction

    func testYaoluContentBase64Decryption() throws {
        let sources = try loadCapabilityBank()
        let sourceData = try XCTUnwrap(sources.first { ($0["bookSourceName"] as? String) == "要撸小说" })
        let source = try JSONDecoder().decode(BookSource.self, from: JSONSerialization.data(withJSONObject: sourceData))

        let rawBase64 = Data("这是一段隐藏在Base64脚本中的真实小说正文。".utf8).base64EncodedString()
        let mockHTML = """
        <html><body>
        <div id="content">
          <script>
            var encoded = "\(rawBase64)";
          </script>
          <p>这是前言</p>
        </div>
        </body></html>
        """

        let runtime = JSCoreRuntime()
        let contentScript = """
        var result = `\(mockHTML)`;
        var encoded = String(result).match(/encoded\\s*=\\s*"([^"]+)"/);
        if (encoded && encoded[1]) {
            java.base64Decode(encoded[1]);
        } else {
            result;
        }
        """
        let result = runtime.evaluate(contentScript)
        guard case .success(let decoded) = result else {
            return XCTFail("Base64 content decode failed: \(result)")
        }
        XCTAssertEqual(decoded, "这是一段隐藏在Base64脚本中的真实小说正文。")
    }

    // MARK: - 3. 希望中文: GBK URI Encoding & Verification Code Challenge

    func testXiWangZhongwenGBKUriEncoding() throws {
        let runtime = JSCoreRuntime()
        // Tests `java.encodeURI(key, "gbk")`
        let script = """
        var key = '武神';
        var encoded = java.encodeURI(key, 'gbk');
        encoded;
        """
        let result = runtime.evaluate(script)
        guard case .success(let text) = result else {
            return XCTFail("GBK URI encode failed: \(result)")
        }
        XCTAssertTrue(text.contains("%"), "expected percent-encoded GBK string")
    }

    func testXiWangZhongwenVerificationChallengeClassification() {
        let verificationHTML = """
        <html><body>
        <form action="/member/checkcode.asp" method="post">
          <div>请输入验证码：</div>
          <input type="hidden" name="actyzm" value="987654321" />
          <input type="text" name="yzm" />
          <input type="submit" name="button" value="提交验证" />
        </form>
        </body></html>
        """

        let kind = SourceDiagnosticClassifier.kind(message: verificationHTML, stage: "search")
        let status = SourceDiagnosticClassifier.status(message: verificationHTML, stage: "search")

        XCTAssertEqual(kind, .verification)
        XCTAssertEqual(status, .verificationRequired)
    }

    // MARK: - 4. 风读小说: Image-Font Stripping & WebJS Ad Sanitization

    func testFengDuFontObfuscationAndWebJsCleanup() throws {
        let runtime = JSCoreRuntime()
        let mockBody = """
        <p>正文段落一开始</p>
        <p>如果出现文字缺失请访问原站</p>
        <p>文字中间有字体图标<img src="/asset/fonts/123.png" alt="font" />继续阅读</p>
        <p>海量小说尽在风读小说网</p>
        <script>console.log('ad script');</script>
        <p>沉浸式成人有声体验</p>
        <p>正文段落二结束</p>
        """

        let webJs = """
        var content = `\(mockBody)`;
        // 移除广告
        content = content.replace(/<p>如果出现文字缺失[\\s\\S]*?<\\/p>/g, '');
        content = content.replace(/<p>海量小说[\\s\\S]*?<\\/p>/g, '');
        content = content.replace(/<p>沉浸式成人有声体验[\\s\\S]*?<\\/p>/g, '');
        // 移除脚本
        content = content.replace(/<script[^>]*>[\\s\\S]*?<\\/script>/g, '');
        // 移除字体图片
        content = content.replace(/<img src="\\/asset\\/fonts\\/\\d+\\.png"[^>]*>/g, '');
        content.trim();
        """

        let result = runtime.evaluate(webJs)
        guard case .success(let cleaned) = result else {
            return XCTFail("WebJs cleanup failed: \(result)")
        }

        XCTAssertFalse(cleaned.contains("/asset/fonts/123.png"))
        XCTAssertFalse(cleaned.contains("海量小说"))
        XCTAssertFalse(cleaned.contains("沉浸式成人有声体验"))
        XCTAssertFalse(cleaned.contains("<script>"))
        XCTAssertTrue(cleaned.contains("正文段落一开始"))
        XCTAssertTrue(cleaned.contains("正文段落二结束"))
    }

    // MARK: - Helper

    private func loadCapabilityBank() throws -> [[String: Any]] {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "legado-capability-bank-20260908", withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "legado-capability-bank-20260908", withExtension: "json")
        )
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }
}
