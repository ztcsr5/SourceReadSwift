import XCTest
@testable import SourceReadSwift

final class ExploreCategoryParserTests: XCTestCase {

    func testParseJSONArray() {
        let json = """
        [
            {"title": "热门精选", "url": "/top/{{page}}.html"},
            {"title": "东方玄幻", "url": "/sort/1/{{page}}.html", "style": {"layout_flexGrow": 1}}
        ]
        """
        let categories = ExploreCategoryParser.parse(exploreUrl: json)
        XCTAssertEqual(categories.count, 2)
        XCTAssertEqual(categories[0].title, "热门精选")
        XCTAssertEqual(categories[0].url, "/top/{{page}}.html")
        XCTAssertNil(categories[0].group)

        XCTAssertEqual(categories[1].title, "东方玄幻")
        XCTAssertEqual(categories[1].url, "/sort/1/{{page}}.html")
        XCTAssertEqual(categories[1].style?["layout_flexGrow"], "1")
    }

    func testParseJSONWithGroupHeaders() {
        let json = """
        [
            {"title": "男生专区", "url": ""},
            {"title": "都市异能", "url": "/dushi/{{page}}.html"},
            {"title": "女生专区", "url": ""},
            {"title": "现代言情", "url": "/yanqing/{{page}}.html"}
        ]
        """
        let categories = ExploreCategoryParser.parse(exploreUrl: json)
        XCTAssertEqual(categories.count, 2)
        XCTAssertEqual(categories[0].title, "都市异能")
        XCTAssertEqual(categories[0].group, "男生专区")

        XCTAssertEqual(categories[1].title, "现代言情")
        XCTAssertEqual(categories[1].group, "女生专区")
    }

    func testParseDoubleColonLines() {
        let text = """
        玄幻小说::/sort/1_{{page}}.html
        仙侠修真::/sort/2_{{page}}.html
        都市爽文::/sort/3_{{page}}.html
        """
        let categories = ExploreCategoryParser.parse(exploreUrl: text)
        XCTAssertEqual(categories.count, 3)
        XCTAssertEqual(categories[0].title, "玄幻小说")
        XCTAssertEqual(categories[0].url, "/sort/1_{{page}}.html")
        XCTAssertEqual(categories[2].title, "都市爽文")
        XCTAssertEqual(categories[2].url, "/sort/3_{{page}}.html")
    }

    func testParseDoubleAmpersandAndGroups() {
        let text = """
        [榜单]
        日榜::/rank/day/{{page}}&&周榜::/rank/week/{{page}}&&月榜::/rank/month/{{page}}
        [分类]
        历史军事::/sort/history/{{page}}&&网游竞技::/sort/game/{{page}}
        """
        let categories = ExploreCategoryParser.parse(exploreUrl: text)
        XCTAssertEqual(categories.count, 5)

        XCTAssertEqual(categories[0].title, "日榜")
        XCTAssertEqual(categories[0].group, "榜单")

        XCTAssertEqual(categories[1].title, "周榜")
        XCTAssertEqual(categories[1].group, "榜单")

        XCTAssertEqual(categories[3].title, "历史军事")
        XCTAssertEqual(categories[3].group, "分类")
    }

    func testParseEmptyOrNil() {
        XCTAssertTrue(ExploreCategoryParser.parse(exploreUrl: nil).isEmpty)
        XCTAssertTrue(ExploreCategoryParser.parse(exploreUrl: "   ").isEmpty)
        XCTAssertTrue(ExploreCategoryParser.parse(exploreUrl: "// comment only").isEmpty)
    }
}
