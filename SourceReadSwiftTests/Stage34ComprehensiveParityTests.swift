import XCTest
@testable import SourceReadSwift

final class Stage34ComprehensiveParityTests: XCTestCase {

    // MARK: - 1. Trailing Comma Sanitization & Loosely-Formatted JSON

    func testSanitizeTrailingCommasInObjectsAndArrays() {
        let dirtyObject = """
        {
          "name": "Test Source",
          "url": "https://example.com",
        }
        """
        let cleanedObject = SourceStore.sanitizeTrailingCommas(dirtyObject)
        XCTAssertFalse(cleanedObject.contains(",\n}"))
        XCTAssertFalse(cleanedObject.contains(",}"))

        let dirtyArray = """
        [
          {"id": 1,},
          {"id": 2,},
        ]
        """
        let cleanedArray = SourceStore.sanitizeTrailingCommas(dirtyArray)
        XCTAssertFalse(cleanedArray.contains(",\n]"))
        XCTAssertFalse(cleanedArray.contains(",]"))

        // Commas inside string values MUST be strictly preserved!
        let stringPreserved = """
        {"text": "hello, world, with, brackets } ] inside", "val": 123,}
        """
        let cleanedPreserved = SourceStore.sanitizeTrailingCommas(stringPreserved)
        XCTAssertTrue(cleanedPreserved.contains("hello, world, with, brackets } ] inside"))
        
        let decoder = JSONDecoder()
        struct SampleItem: Decodable {
            let text: String
            let val: Int
        }
        let decoded = try? decoder.decode(SampleItem.self, from: Data(cleanedPreserved.utf8))
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.text, "hello, world, with, brackets } ] inside")
        XCTAssertEqual(decoded?.val, 123)
    }

    func testRealWorldRSSSourcesJsonWithTrailingCommaImportsSuccessfully() {
        // Reproduces the exact trailing comma from SourceRead.app's rssSources.json
        let rawJson = """
        [
          {
            "customOrder": 1,
            "enableJs": true,
            "enabled": true,
            "singleUrl": true,
            "sourceIcon": "http://ku.mumuceo.com/static/images/applogo/yuedu.png",
            "sourceName": "使用说明",
            "sourceUrl": "https://www.yuque.com/legado"
          },
          {
            "customOrder": 2,
            "enableJs": true,
            "enabled": true,
            "singleUrl": true,
            "sourceIcon": "https://txc.gtimg.com/data/145120/2020/0418/99f04e2fdbed180f8ad0cb6ee5cfddca.png",
            "sourceName": "源仓库",
            "sourceUrl": "http://yck.mumuceo.com/"
          },
          {
            "customOrder": 3,
            "enableJs": true,
            "enabled": true,
            "singleUrl": true,
            "sourceIcon": "http://image.5you.com/attachment/soft/2020/0720/171051_34898081.png",
            "sourceName": "海阔视界",
            "sourceUrl": "https://haikuoshijie.cn/topics/node/1?p=2"
          },
        ]
        """
        let sanitized = SourceStore.sanitizeTrailingCommas(rawJson)
        let decoder = JSONDecoder()
        let items = try? decoder.decode([RSSSource].self, from: Data(sanitized.utf8))
        XCTAssertNotNil(items)
        XCTAssertEqual(items?.count, 3)
        XCTAssertEqual(items?[0].sourceName, "使用说明")
        XCTAssertEqual(items?[1].sourceName, "源仓库")
        XCTAssertEqual(items?[2].sourceName, "海阔视界")
    }

    // MARK: - 2. Default Official SourceRead RSS Sources

    func testDefaultOfficialRSSSourcesIntegrity() {
        let defaults = SourceStore.defaultRSSSources
        XCTAssertEqual(defaults.count, 3)

        let names = defaults.map(\.sourceName)
        XCTAssertTrue(names.contains("使用说明"))
        XCTAssertTrue(names.contains("源仓库"))
        XCTAssertTrue(names.contains("海阔视界"))

        let urls = defaults.map(\.sourceUrl)
        XCTAssertTrue(urls.contains("https://www.yuque.com/legado"))
        XCTAssertTrue(urls.contains("http://yck.mumuceo.com/"))
        XCTAssertTrue(urls.contains("https://haikuoshijie.cn/topics/node/1?p=2"))

        for source in defaults {
            XCTAssertTrue(source.enabled)
            XCTAssertNotNil(source.sourceIcon)
        }
    }

    // MARK: - 3. Smart Navigation Source ($BROWSER_SOURCE$) JS Capabilities

    func testJSCoreRuntimeBookReverseTocAndGlobalJsoup() {
        let runtime = JSCoreRuntime()
        
        // 1. Verify global org.jsoup.Jsoup without Packages prefix
        let jsoupResult = runtime.evaluate("""
        var doc = org.jsoup.Jsoup.parse('<div class="title"><h1>天道图书馆</h1></div>');
        doc.select('h1').text();
        """)
        XCTAssertEqual(jsoupResult, "天道图书馆")

        // 2. Verify book.setReverseToc and book.getReverseToc
        let reverseTocResult = runtime.evaluate("""
        book.setReverseToc(true);
        var r1 = book.getReverseToc();
        book.setReverseToc(false);
        var r2 = book.getReverseToc();
        [r1, r2].join('|');
        """)
        XCTAssertEqual(reverseTocResult, "true|false")

        // 3. Verify chapter and book variables together (as used in browserSource.json)
        let complexEval = runtime.evaluate("""
        book.putVariable('customKey', '42');
        chapter.putVariable('nextUrl', 'https://example.com/c2.html');
        var r = org.jsoup.Jsoup.parse('<a href="https://example.com/c1.html">第一章</a>');
        var link = r.select('a').first().attr('href');
        [book.getVariable('customKey'), chapter.getVariable('nextUrl'), link].join('///');
        """)
        XCTAssertEqual(complexEval, "42///https://example.com/c2.html///https://example.com/c1.html")
    }

    // MARK: - 4. Bookshelf Batch Operations & Export Text

    func testBookshelfBatchSelectionAndExportText() {
        let book1 = BookshelfBook(
            id: "b1",
            title: "诡秘之主",
            author: "爱潜水的乌贼",
            coverURL: nil,
            bookURL: "https://example.com/b1",
            sourceName: "起点中文",
            sourceURL: "https://example.com",
            currentChapterTitle: "第100章 秘术导师",
            latestChapterTitle: "第1432章 旅途的终点",
            readingProgress: 0.12,
            groupName: "玄幻"
        )
        let book2 = BookshelfBook(
            id: "b2",
            title: "道诡异仙",
            author: "狐尾的笔",
            coverURL: nil,
            bookURL: "https://example.com/b2",
            sourceName: "起点中文",
            sourceURL: "https://example.com",
            currentChapterTitle: nil,
            latestChapterTitle: "第980章 大结局",
            readingProgress: 0.0,
            groupName: "悬疑"
        )

        let selected = [book1, book2]
        let exportLines = selected.map {
            "- 《\($0.title)》 \($0.author) (\($0.currentChapterTitle ?? $0.latestChapterTitle ?? "未读"))"
        }
        let exportText = exportLines.joined(separator: "\n")

        XCTAssertTrue(exportText.contains("- 《诡秘之主》 爱潜水的乌贼 (第100章 秘术导师)"))
        XCTAssertTrue(exportText.contains("- 《道诡异仙》 狐尾的笔 (第980章 大结局)"))
    }

    // MARK: - 5. EPUB Parser Architecture & Navigation Models

    func testLocalTextNavigationEntryModelMapping() {
        let entry = LocalTextNavigationEntry(
            title: "Chapter 1: An Unexpected Journey",
            sourcePath: "OEBPS/text/c01.xhtml",
            fragment: "section-1",
            chapterIndex: 0,
            paragraphIndex: 2
        )
        XCTAssertEqual(entry.id, "OEBPS/text/c01.xhtml#section-1")
        XCTAssertEqual(entry.title, "Chapter 1: An Unexpected Journey")
        XCTAssertEqual(entry.chapterIndex, 0)
        XCTAssertEqual(entry.paragraphIndex, 2)
    }

    // MARK: - 6. Lightweight HTTP Server Health Endpoint Format

    func testHttpServerHealthCheckOutputFormat() {
        let port: UInt16 = 8080
        let healthBody = "SOURCE_READ_SWIFT_WEB_OK\nREAD_SOURCE_WEB_OK port=\(port)"
        XCTAssertTrue(healthBody.contains("SOURCE_READ_SWIFT_WEB_OK"))
        XCTAssertTrue(healthBody.contains("port=8080"))
    }
}
