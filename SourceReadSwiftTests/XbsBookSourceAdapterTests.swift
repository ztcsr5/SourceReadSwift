import XCTest
@testable import SourceReadSwift

final class XbsBookSourceAdapterTests: XCTestCase {

    func testXXTEADecryptAndDetection() {
        let key = XbsBookSourceAdapter.defaultKey
        let originalText = "{\"sourceName\":\"测试书源\",\"sourceUrl\":\"https://test.com\",\"searchBook\":{\"parserID\":\"DOM\"}}"
        var data = originalText.data(using: .utf8)!
        // Pad to multiple of 4
        while data.count % 4 != 0 {
            data.append(0)
        }

        // Encrypt data using XXTEA formula
        let n = data.count / 4
        var v = [UInt32](repeating: 0, count: n)
        data.withUnsafeBytes { ptr in
            let u32Ptr = ptr.bindMemory(to: UInt32.self)
            for i in 0..<n {
                v[i] = CFSwapInt32LittleToHost(u32Ptr[i])
            }
        }
        var k = [UInt32](repeating: 0, count: 4)
        key.prefix(16).withUnsafeBytes { ptr in
            let u32Ptr = ptr.bindMemory(to: UInt32.self)
            for i in 0..<4 {
                k[i] = CFSwapInt32LittleToHost(u32Ptr[i])
            }
        }
        let delta: UInt32 = 0x9E3779B9
        let rounds = 6 + 52 / n
        var sum: UInt32 = 0
        var z = v[n - 1]
        for _ in 0..<rounds {
            sum = sum &+ delta
            let e = (sum >> 2) & 3
            for p in 0..<n {
                let y = v[(p + 1) % n]
                let term1 = ((z >> 5) ^ (y << 2)) &+ ((y >> 3) ^ (z << 4))
                let term2 = (sum ^ y) &+ (k[Int((UInt32(p) & 3) ^ e)] ^ z)
                v[p] = v[p] &+ (term1 ^ term2)
                z = v[p]
            }
        }
        var encrypted = Data(capacity: n * 4)
        for i in 0..<n {
            var val = CFSwapInt32HostToLittle(v[i])
            withUnsafeBytes(of: &val) { encrypted.append(contentsOf: $0) }
        }

        // Test decrypt
        guard let decrypted = XbsBookSourceAdapter.xxteaDecrypt(data: encrypted, key: key),
              let decryptedStr = String(data: decrypted, encoding: .utf8) else {
            return XCTFail("XXTEA decrypt returned nil")
        }
        XCTAssertTrue(decryptedStr.contains("测试书源"))

        // Test format detection
        XCTAssertTrue(XbsBookSourceAdapter.isXbsJSON(originalText))
        XCTAssertTrue(XbsBookSourceAdapter.isXbsData(encrypted))
    }

    func testXbsNovelConversionAndFiltering() {
        let xbsJSON = """
        {
          "独步小说": {
            "sourceName": "独步小说",
            "sourceUrl": "https://www.dbxsz.com",
            "sourceType": "text",
            "weight": "7777",
            "searchBook": {
              "host": "https://www.dbxsz.com",
              "requestInfo": "/plus/search.php?q=%@keyWord",
              "list": "//tbody/tr",
              "bookName": "//td[1]/a/@title",
              "author": "//td[2]",
              "detailUrl": "//td[1]/a/@href"
            },
            "chapterList": {
              "host": "https://www.dbxsz.com",
              "list": "//div[@id=\"all-chapter\"]//a",
              "title": "//@title",
              "url": "//@href"
            },
            "chapterContent": {
              "host": "https://www.dbxsz.com",
              "content": "//*[@id=\"cont-body\"]"
            }
          },
          "坏源番茄": {
            "sourceName": "坏源番茄",
            "sourceUrl": "https://souhh.com",
            "sourceType": "text",
            "searchBook": { "host": "https://souhh.com" }
          },
          "某视频源": {
            "sourceName": "某视频源",
            "sourceUrl": "https://video.example.com",
            "sourceType": "video",
            "searchBook": { "host": "https://video.example.com" }
          },
          "某漫画源": {
            "sourceName": "某漫画源",
            "sourceUrl": "https://comic.example.com",
            "category": "comic",
            "searchBook": { "host": "https://comic.example.com" }
          }
        }
        """

        let sources = XbsBookSourceAdapter.importSources(from: xbsJSON)
        // Video, comic, and dead domain (souhh.com) must be filtered out!
        XCTAssertEqual(sources.count, 1)
        guard let dubo = sources.first else {
            return XCTFail("Expected 独步小说 to be converted")
        }
        XCTAssertEqual(dubo.bookSourceName, "独步小说")
        XCTAssertEqual(dubo.bookSourceUrl, "https://www.dbxsz.com")
        XCTAssertEqual(dubo.searchUrl, "https://www.dbxsz.com/plus/search.php?q={{key}}")
        XCTAssertEqual(dubo.ruleSearch?.fields["bookList"], "//tbody/tr")
        XCTAssertEqual(dubo.ruleSearch?.fields["name"], "//td[1]/a/@title")
        XCTAssertEqual(dubo.ruleToc?.fields["chapterList"], "//div[@id=\"all-chapter\"]//a")
        XCTAssertEqual(dubo.ruleContent?.fields["content"], "//*[@id=\"cont-body\"]")
        XCTAssertEqual(dubo.bookSourceGroup, "香色闺阁")
        XCTAssertEqual(dubo.weight, 7777)
    }

    func testBookDetailParserDynamicTocUrl() throws {
        let executionContext = RuleExecutionContext()
        executionContext.put("998877", for: "book_id")

        let source = BookSource(
            bookSourceName: "番茄测试",
            bookSourceUrl: "https://fanqienovel.com",
            ruleBookInfo: SourceRule(fields: [
                "name": "$.data.book_name",
                "tocUrl": "https://fanqienovel.com/api/reader/full?bookId=@get:{book_id}"
            ])
        )

        let parser = BookDetailParser(executionContext: executionContext)
        let json = "{\"data\": {\"book_name\": \"十日终焉\"}}"
        let jsonResponse = SourceResponse(
            url: URL(string: "https://fanqienovel.com/page/detail")!,
            statusCode: 200,
            headers: [:],
            body: json,
            data: Data(json.utf8)
        )

        let searchBook = SearchBook(
            name: "十日终焉",
            author: "杀虫队队员",
            coverUrl: nil,
            bookUrl: "https://fanqienovel.com/page/detail",
            sourceName: source.bookSourceName,
            sourceUrl: source.bookSourceUrl
        )
        let result = parser.parse(source: source, book: searchBook, response: jsonResponse)

        guard case .success(let detail) = result else {
            return XCTFail("detail parse failed")
        }

        XCTAssertEqual(detail.name, "十日终焉")
        XCTAssertEqual(detail.tocUrl, "https://fanqienovel.com/api/reader/full?bookId=998877")
    }
}
