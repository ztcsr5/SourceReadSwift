import XCTest
@testable import SourceReadSwift

final class HuaHuoBookSourceAdapterTests: XCTestCase {

    func testHuaHuoJSONDetection() {
        let sampleJSON = """
        {
            "sourceName": "花火精选小说",
            "sourceUrl": "https://huahuo.example.com",
            "ruleSearch": {
                "searchBookList": ".book-item",
                "searchName": ".title@text",
                "searchAuthor": ".author@text",
                "searchBookUrl": "a@href"
            },
            "ruleBookInfo": {
                "infoName": "h1@text",
                "infoTocUrl": "a.toc@href"
            },
            "ruleToc": {
                "tocList": ".chapter-list a",
                "tocName": "text",
                "tocUrl": "href"
            },
            "ruleContent": {
                "content": "#content@text",
                "nextContentUrl": "a.next@href"
            }
        }
        """

        XCTAssertTrue(HuaHuoBookSourceAdapter.isHuaHuoJSON(sampleJSON))
        XCTAssertTrue(HuaHuoBookSourceAdapter.isHuaHuoData(Data(sampleJSON.utf8)))

        let nonHuaHuo = """
        { "bookSourceName": "Legado Source", "bookSourceUrl": "https://legado.com" }
        """
        XCTAssertFalse(HuaHuoBookSourceAdapter.isHuaHuoJSON(nonHuaHuo))
    }

    func testHuaHuoAdaptation() {
        let sampleJSON = """
        [
            {
                "sourceName": "花火测试源",
                "sourceUrl": "https://huahuo.test.org",
                "sourceGroup": "精品推荐",
                "searchUrl": "https://huahuo.test.org/search?q={{key}}",
                "ruleSearch": {
                    "searchBookList": "ul.list li",
                    "searchName": ".name@text",
                    "searchAuthor": ".author@text",
                    "searchBookUrl": ".link@href"
                },
                "ruleToc": {
                    "tocList": "#chapters a",
                    "tocName": "text",
                    "tocUrl": "href"
                },
                "ruleContent": {
                    "content": "#art-content@text"
                }
            }
        ]
        """

        let sources = HuaHuoBookSourceAdapter.importSources(from: sampleJSON)
        XCTAssertEqual(sources.count, 1)

        let source = sources[0]
        XCTAssertEqual(source.bookSourceName, "花火测试源")
        XCTAssertEqual(source.bookSourceUrl, "https://huahuo.test.org")
        XCTAssertEqual(source.bookSourceGroup, "精品推荐")
        XCTAssertEqual(source.searchUrl, "https://huahuo.test.org/search?q={{key}}")
        XCTAssertEqual(source.ruleSearch?.fields["bookList"], "ul.list li")
        XCTAssertEqual(source.ruleSearch?.fields["name"], ".name@text")
        XCTAssertEqual(source.ruleToc?.fields["chapterList"], "#chapters a")
        XCTAssertEqual(source.ruleContent?.fields["content"], "#art-content@text")
    }
}
