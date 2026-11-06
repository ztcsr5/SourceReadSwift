import XCTest
@testable import SourceReadSwift

final class HuaHuoBookSourceAdapterTests: XCTestCase {

    func testComicMetadataAndScriptLibrarySurviveImportAndPersistence() throws {
        let exported = ##"{"sourceName":"Comic fixture","sourceUrl":"https://comic.fixture.invalid","bookSourceType":2,"enabled":false,"weight":17,"header":{"User-Agent":"Fixture Reader"},"jsLib":"function fixture(){return 7;}","concurrentRate":"3/1000","loginCheckJs":"result","loginUi":[{"name":"account","type":"text"}],"customConfig":{"layout":"strip"},"ruleSearch":{"searchBookList":".item","searchName":"h2@text"}}"##
        let source = try XCTUnwrap(HuaHuoBookSourceAdapter.importSources(from: exported).first)
        let restored = try JSONDecoder().decode(BookSource.self, from: JSONEncoder().encode(source))
        for candidate in [source, restored] {
            XCTAssertEqual(candidate.bookSourceType, 2)
            XCTAssertFalse(candidate.enabled)
            XCTAssertEqual(candidate.weight, 17)
            XCTAssertEqual(candidate.raw["jsLib"], "function fixture(){return 7;}")
            XCTAssertEqual(candidate.concurrentRate, "3/1000")
            XCTAssertEqual(candidate.loginCheckJs, "result")
            let headers = try XCTUnwrap(candidate.header).data(using: .utf8)!
            XCTAssertEqual((try JSONSerialization.jsonObject(with: headers) as? [String: String])?["User-Agent"], "Fixture Reader")
            let login = try XCTUnwrap(candidate.loginUi).data(using: .utf8)!
            XCTAssertNotNil(try JSONSerialization.jsonObject(with: login) as? [[String: Any]])
            let config = try XCTUnwrap(candidate.customConfig).data(using: .utf8)!
            XCTAssertEqual((try JSONSerialization.jsonObject(with: config) as? [String: String])?["layout"], "strip")
            XCTAssertEqual(candidate.ruleSearch?.fields["bookList"], ".item")
        }
    }

    func testLegadoPaginationFieldDoesNotMisclassifyTheSourceAsHuaHuo() {
        let exported = ##"{"bookSourceName":"Canonical","bookSourceUrl":"https://fixture.invalid","ruleContent":{"content":"#body@text","nextContentUrl":"a.next@href"}}"##
        XCTAssertFalse(HuaHuoBookSourceAdapter.isHuaHuoJSON(exported))
    }

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

    func testHuaHuoAdaptationMarksSourceFormat() {
        let sampleJSON = """
        [
            {
                "sourceName": "花火格式源",
                "sourceUrl": "https://huahuo.format.org",
                "searchUrl": "https://huahuo.format.org/search?q={{key}}",
                "ruleSearch": {
                    "searchBookList": ".item",
                    "searchName": ".name@text",
                    "searchBookUrl": "a@href"
                }
            }
        ]
        """

        let sources = HuaHuoBookSourceAdapter.importSources(from: sampleJSON)

        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.raw["sourceFormat"], "huahuo")
        XCTAssertEqual(sources.first?.sourceFormat, .huahuo)
    }
}
