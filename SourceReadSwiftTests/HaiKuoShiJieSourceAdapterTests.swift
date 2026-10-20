import XCTest
@testable import SourceReadSwift

final class HaiKuoShiJieSourceAdapterTests: XCTestCase {

    func testHaiKuoJSONDetection() {
        let sampleJSON = """
        {
            "title": "海阔影视小说",
            "url": "https://haikuo.example.com",
            "find_rule": "js: fetch(url)",
            "search_rule": "js: search(key)",
            "col_type": "movie_1"
        }
        """

        XCTAssertTrue(HaiKuoShiJieSourceAdapter.isHaiKuoJSON(sampleJSON))
        XCTAssertTrue(HaiKuoShiJieSourceAdapter.isHaiKuoData(Data(sampleJSON.utf8)))

        let plain = "{\"title\":\"Plain Item\"}"
        XCTAssertFalse(HaiKuoShiJieSourceAdapter.isHaiKuoJSON(plain))
    }

    func testHaiKuoAdaptation() {
        let sampleJSON = """
        [
            {
                "title": "海阔小说源",
                "url": "https://haikuo.novel.org",
                "group": "海阔影视",
                "search_url": "https://haikuo.novel.org/s?wd={{key}}",
                "search_rule": ".search-results li",
                "find_rule": ".category-list li",
                "ua": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"
            }
        ]
        """

        let sources = HaiKuoShiJieSourceAdapter.importSources(from: sampleJSON)
        XCTAssertEqual(sources.count, 1)

        let source = sources[0]
        XCTAssertEqual(source.bookSourceName, "海阔小说源")
        XCTAssertEqual(source.bookSourceUrl, "https://haikuo.novel.org")
        XCTAssertEqual(source.bookSourceGroup, "海阔影视")
        XCTAssertEqual(source.searchUrl, "https://haikuo.novel.org/s?wd={{key}}")
        XCTAssertEqual(source.ruleSearch?.fields["bookList"], ".search-results li")
        XCTAssertEqual(source.ruleExplore?.fields["bookList"], ".category-list li")
        XCTAssertTrue(source.header?.contains("iPhone") == true)
    }

    func testHaiKuoAdaptationMarksSourceFormat() {
        let sampleJSON = """
        [
            {
                "title": "海阔格式源",
                "url": "https://haikuo.format.org",
                "group": "海阔影视",
                "search_url": "https://haikuo.format.org/s?wd={{key}}",
                "search_rule": ".result li"
            }
        ]
        """

        let sources = HaiKuoShiJieSourceAdapter.importSources(from: sampleJSON)

        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.raw["sourceFormat"], "haikuo")
        XCTAssertEqual(sources.first?.sourceFormat, .haikuo)
    }

    func testGenericTitleUrlGroupJSONIsNotHaiKuo() {
        let generic = """
        [
            {
                "title": "普通站点",
                "url": "https://generic.example.com",
                "group": "普通分组"
            }
        ]
        """

        XCTAssertFalse(HaiKuoShiJieSourceAdapter.isHaiKuoJSON(generic))
    }
}
