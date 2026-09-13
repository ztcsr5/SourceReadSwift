import XCTest
import SwiftSoup
@testable import SourceReadSwift

final class CloudCollectionRuleTests: XCTestCase {
    // MARK: - 1. Multi-Index and Slicing Selector Tests

    func testMultiIndexExtraction() throws {
        let html = """
        <html><body>
          <div class="synopsisArea_detail">
            <p>P0: Author</p>
            <p>P1: Urban</p>
            <p>P2: Ongoing</p>
            <p>P3: 100 Chapters</p>
            <p>P4: Hot</p>
          </div>
        </body></html>
        """
        let doc = try SwiftSoup.parse(html)
        let extractor = HtmlRuleExtractor()

        // Test p.1:2 (PO文屋)
        let val1 = try extractor.value(
            from: doc,
            rule: ".synopsisArea_detail p.1:2@text",
            baseUrl: URL(string: "https://example.com")!
        )
        XCTAssertTrue(val1.contains("P1: Urban"))
        XCTAssertTrue(val1.contains("P2: Ongoing"))
        XCTAssertFalse(val1.contains("P0: Author"))

        // Test p.1:2:4 (PO文屋 detail)
        let val2 = try extractor.value(
            from: doc,
            rule: ".synopsisArea_detail p.1:2:4@text",
            baseUrl: URL(string: "https://example.com")!
        )
        XCTAssertTrue(val2.contains("P1: Urban"))
        XCTAssertTrue(val2.contains("P2: Ongoing"))
        XCTAssertTrue(val2.contains("P4: Hot"))
        XCTAssertFalse(val2.contains("P3: 100 Chapters"))
    }

    func testNegativeMultiIndexExtraction() throws {
        let html = """
        <div>
          <span>Span 0</span>
          <span>Span 1</span>
          <span>Span 2 (Idx -3)</span>
          <span>Span 3 (Idx -2)</span>
          <span>Span 4 (Idx -1)</span>
        </div>
        """
        let doc = try SwiftSoup.parse(html)
        let extractor = HtmlRuleExtractor()

        // Test span.-3:-4:-1 (三八小说)
        let val = try extractor.value(
            from: doc,
            rule: "span.-3:-4:-1@text",
            baseUrl: URL(string: "https://example.com")!
        )
        XCTAssertTrue(val.contains("Span 2"))
        XCTAssertTrue(val.contains("Span 1"))
        XCTAssertTrue(val.contains("Span 4"))
        XCTAssertFalse(val.contains("Span 0"))
    }

    func testExcludeMultiIndex() throws {
        let html = """
        <ul class="pages">
          <li><a href="/p0">Prev</a></li>
          <li><a href="/p1">1</a></li>
          <li><a href="/p2">2</a></li>
          <li><a href="/p3">3</a></li>
          <li><a href="/p4">Next</a></li>
        </ul>
        """
        let doc = try SwiftSoup.parse(html)
        let extractor = HtmlRuleExtractor()

        // Test class.pages@tag.ul@tag.li.!0:1:-1@tag.a@href (看书网)
        let links = try extractor.value(
            from: doc,
            rule: "class.pages@tag.ul@tag.li.!0:1:-1@tag.a@href",
            baseUrl: URL(string: "https://example.com")!
        )
        XCTAssertTrue(links.contains("https://example.com/p2"))
        XCTAssertTrue(links.contains("https://example.com/p3"))
        XCTAssertFalse(links.contains("https://example.com/p0"))
        XCTAssertFalse(links.contains("https://example.com/p1"))
        XCTAssertFalse(links.contains("https://example.com/p4"))
    }

    // MARK: - 2. JavaImporter and Cryptographic Shims

    func testJavaImporterAndCipherPipeline() throws {
        let runtime = JSCoreRuntime()
        // Exact decode script structure from 阅读助手（优+++）
        let script = """
        var javaImport = new JavaImporter();
        javaImport.importPackage(
            Packages.java.lang,
            Packages.javax.crypto.spec,
            Packages.javax.crypto,
            Packages.java.util
        );
        var res = "";
        with(javaImport) {
            function decode(content) {
                var ivEncData = Base64.getDecoder().decode(String(content));
                var key = SecretKeySpec(String("242ccb8230d709e1").getBytes(), "AES");
                var iv = IvParameterSpec(Arrays.copyOfRange(ivEncData, 0, 16));
                var chipher = Cipher.getInstance("AES/CBC/PKCS5Padding");
                chipher.init(2, key, iv);
                return String(chipher.doFinal(Arrays.copyOfRange(ivEncData, 16, ivEncData.length)));
            }
            // Encrypt "Hello Legado 3.0" with AES-128-CBC
            var plain = "Hello Legado 3.0";
            var enc = java.cipherEncodeToBase64String(plain, "242ccb8230d709e1", "0123456789abcdef", "AES/CBC/PKCS5Padding");
            // Prefix 16-byte IV to ciphertext bytes
            var ivBytes = java.strToBytes("0123456789abcdef");
            var encBytes = java.base64DecodeToByteArray(enc);
            var combined = ivBytes.concat(encBytes);
            var combinedB64 = java.base64Encode(combined);
            res = decode(combinedB64);
        }
        res;
        """
        let result = runtime.evaluate(script)
        switch result {
        case .success(let output):
            XCTAssertEqual(output, "Hello Legado 3.0")
        case .failure(let error):
            XCTFail("JavaImporter cipher evaluation failed: \(error)")
        }
    }

    func testJavaUtilityMethods() throws {
        let runtime = JSCoreRuntime()
        let script = """
        var aid = java.androidId();
        var uuid = java.randomUUID().toString();
        var toast = java.toast("testing");
        var ua = java.getWebViewUA();
        var open = java.openUrl("https://example.com");
        JSON.stringify({ aid: aid, uuidLen: uuid.length, toast: toast, hasUA: ua.length > 0, open: open });
        """
        let result = runtime.evaluate(script)
        switch result {
        case .success(let output):
            guard let data = output.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                XCTFail("Output was not valid json: \(output)")
                return
            }
            XCTAssertEqual(dict["aid"] as? String, "a1b2c3d4e5f60718")
            XCTAssertEqual(dict["uuidLen"] as? Int, 36)
            XCTAssertEqual(dict["toast"] as? String, "")
            XCTAssertEqual(dict["hasUA"] as? Bool, true)
            XCTAssertEqual(dict["open"] as? String, "")
        case .failure(let error):
            XCTFail("Java utility methods evaluation failed: \(error)")
        }
    }

    func testBookAndChapterCustomVariable() throws {
        let runtime = JSCoreRuntime()
        let book = SearchBook(
            name: "Test Novel",
            author: "Author A",
            coverUrl: nil,
            bookUrl: "https://example.com/b/1",
            sourceName: "Source 1",
            sourceUrl: "https://example.com",
            intro: nil
        )
        let script = """
        book.putCustomVariable("custom_payload_data");
        var val = book.getCustomVariable();
        book.putVariable("key2", "val2");
        var val2 = book.getVariable("key2");
        val + " | " + val2;
        """
        let result = runtime.evaluate(script, variables: ["book": book])
        switch result {
        case .success(let output):
            XCTAssertEqual(output, "custom_payload_data | val2")
        case .failure(let error):
            XCTFail("Custom variable evaluation failed: \(error)")
        }
    }

    // MARK: - 3. Trailing JSON Options Preservation in Absolutize

    func testAbsolutizePreservesTrailingOptions() throws {
        let extractor = HtmlRuleExtractor()
        let base = URL(string: "http://119.45.176.116:5006/book/123")!
        let relativeWithOptions = "/chapterContent,{\"body\":{\"book_id\":123,\"chapterIdList\":\"456,\"},\"method\":\"POST\"}"
        let absolutized = extractor.absolutize(relativeWithOptions, base: base)
        XCTAssertTrue(absolutized.hasPrefix("http://119.45.176.116:5006/chapterContent,"))
        XCTAssertTrue(absolutized.contains("\"method\":\"POST\""))
        XCTAssertTrue(absolutized.contains("\"book_id\":123"))
    }

    // MARK: - 4. SearchURLResolver JS Post-Processing

    func testSearchURLResolverWithJSReturningOptions() throws {
        let source = BookSource(
            bookSourceName: "米读小说",
            bookSourceUrl: "https://api.midureader.com",
            searchUrl: """
            @js:
            var option = {
                "method": "POST",
                "body": "app=midu&keyword={{key}}&page={{page-1}}"
            };
            "https://api.midureader.com/fiction/search/search," + JSON.stringify(option)
            """
        )
        let resolver = SearchURLResolver()
        let result = resolver.resolve(source: source, keyword: "剑来", page: 1)
        switch result {
        case .success(let url):
            XCTAssertTrue(url.contains("https://api.midureader.com/fiction/search/search,"))
            XCTAssertTrue(url.contains("\"method\":\"POST\""))
            // Verify {{key}} and arithmetic {{page-1}} got interpolated
            XCTAssertTrue(url.contains("keyword=%E5%89%91%E6%9D%A5"))
            XCTAssertTrue(url.contains("page=0"))
        case .failure(let error):
            XCTFail("SearchURLResolver failed: \(error)")
        }
    }

    // MARK: - 5. BookSource Lossless Decoding of Real-world Sources

    func testDecodeRealWorldSourceJSON() throws {
        let sample = """
        {
            "bookSourceName": "🎉 米读小说",
            "bookSourceUrl": "http://api.midukanshu.com",
            "bookSourceType": 0,
            "customOrder": 0,
            "enabled": true,
            "header": "{\\\"User-Agent\\\":\\\"Mozilla/5.0\\\"}",
            "searchUrl": "/api/v1/search?key={{key}}",
            "ruleSearch": {
                "bookList": "$.data.*",
                "name": "original_title",
                "author": "original_author",
                "intro": "🏷️ 标签：{{$.ptags}}\\n🔖 简介：{{$.intro}}",
                "coverUrl": "image_link",
                "bookUrl": "/book/{{$.id}}"
            },
            "ruleToc": {
                "chapterList": "$.[*]",
                "chapterName": "title",
                "chapterUrl": "id"
            },
            "ruleContent": {
                "content": "$..content"
            }
        }
        """
        let data = Data(sample.utf8)
        let source = try JSONDecoder().decode(BookSource.self, from: data)
        XCTAssertEqual(source.bookSourceName, "🎉 米读小说")
        XCTAssertEqual(source.ruleSearch?.fields["name"], "original_title")
        XCTAssertEqual(source.ruleToc?.fields["chapterName"], "title")

        // Test template interpolation on search item
        let extractor = JSONRuleExtractor()
        let item: [String: Any] = [
            "original_title": "凡人修仙传",
            "ptags": "仙侠,修真",
            "intro": "凡人小子的修仙之路"
        ]
        let introText = extractor.string(
            from: item,
            rule: source.ruleSearch?.fields["intro"],
            fallbackKeys: []
        )
        XCTAssertTrue(introText?.contains("仙侠,修真") == true)
        XCTAssertTrue(introText?.contains("凡人小子的修仙之路") == true)
    }
}
