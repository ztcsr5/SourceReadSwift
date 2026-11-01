import XCTest
@testable import SourceReadSwift

final class WebsiteSourceInferenceTests: XCTestCase {
    private var catalog: WebsitePageSample {
        .init(url: URL(string: "https://novel.example/book/1/")!, html: """
        <html><body><nav><a href='/'>首页</a></nav><h1>示例长篇</h1>
        <div id='catalog'><a href='1.html'>第一章 归来</a><a href='2.html'>第二章 出发</a><a href='3.html'>第三章 山海</a></div>
        <form><input type='password' value='DO-NOT-EXPORT'></form></body></html>
        """)
    }
    private var chapter: WebsitePageSample {
        .init(url: URL(string: "https://novel.example/book/1/2.html")!, html: "<h1>第二章 出发</h1><div id='content'>" +
              (0..<10).map { "<p>第\($0)段。远山间的故事继续，章节规则应保留真实正文，而不是导航链接或登录表单。</p>" }.joined() + "</div>")
    }

    func testGeneratedRulesRunThroughProductionParsersAndExplore() throws {
        let draft = try WebsiteSourceInference.infer(catalog: catalog, chapter: chapter, name: "我的站点")
        XCTAssertEqual(draft.chapterCount, 3)
        XCTAssertEqual(draft.tocSelector, "#catalog")
        XCTAssertEqual(draft.contentSelector, "#content")
        XCTAssertTrue(draft.preview.joined().contains("第0段"))
        XCTAssertNil(draft.source.searchUrl, "One catalog page is not evidence of a search protocol")
        let categories = ExploreCategoryParser.parse(exploreUrl: draft.source.exploreUrl)
        XCTAssertEqual(categories.count, 1, "Imported source must have a reachable discovery entry, not a bare URL treated as a group header")
        XCTAssertEqual(categories.first?.url, catalog.url.absoluteString)
        let response = SourceResponse(url: catalog.url, statusCode: 200, headers: [:], body: catalog.html, data: Data(catalog.html.utf8))
        let books = try SearchResultParser().parse(source: draft.source, response: response, ruleOverride: draft.source.ruleExplore).get()
        XCTAssertEqual(books.first?.name, "示例长篇")
        XCTAssertEqual(books.first?.bookUrl, catalog.url.absoluteString)
        let detail = try BookDetailParser().parse(source: draft.source, book: draft.example, response: response).get()
        XCTAssertEqual(detail.tocUrl, catalog.url.absoluteString)
        let exported = String(decoding: try JSONEncoder().encode(draft.source), as: UTF8.self)
        XCTAssertFalse(exported.contains("DO-NOT-EXPORT"))
        XCTAssertFalse(exported.contains("<html>"))
        XCTAssertFalse(exported.contains("Cookie"))
    }

    func testRejectsCrossOriginAndMissingBodyRatherThanImportingPretendSuccess() throws {
        let external = WebsitePageSample(url: URL(string: "https://other.example/book/1/2.html")!, html: chapter.html)
        XCTAssertThrowsError(try WebsiteSourceInference.infer(catalog: catalog, chapter: external, name: "x"))
        let empty = WebsitePageSample(url: chapter.url, html: "<nav>只有登录和导航</nav>")
        XCTAssertThrowsError(try WebsiteSourceInference.infer(catalog: catalog, chapter: empty, name: "x"))
        let unlisted = WebsitePageSample(url: URL(string: "https://novel.example/not-in-catalog")!, html: chapter.html)
        XCTAssertThrowsError(try WebsiteSourceInference.infer(catalog: catalog, chapter: unlisted, name: "x"))
    }

    func testURLAndSizeBoundaryAndEditableSelectors() throws {
        for address in ["file:///private/data", "javascript:alert(1)", "https://user:pass@novel.example/", "https://novel.example/?access_token=secret"] {
            XCTAssertNil(WebsiteSourceInference.validURL(address))
        }
        XCTAssertNotNil(WebsiteSourceInference.validURL("https://novel.example/book?id=12"))
        let draft = try WebsiteSourceInference.infer(catalog: catalog, chapter: chapter, name: "x", tocCSS: "#catalog", contentCSS: "#content")
        XCTAssertEqual(draft.chapterCount, 3)
        XCTAssertThrowsError(try WebsiteSourceInference.infer(catalog: catalog, chapter: chapter, name: "x", tocCSS: "#missing", contentCSS: "#content"))
        XCTAssertThrowsError(try WebsiteSourceInference.infer(catalog: catalog, chapter: chapter, name: "x", tocCSS: "#catalog", contentCSS: "#missing"))
        let oversized = WebsitePageSample(url: chapter.url, html: String(repeating: "中", count: 700_000))
        XCTAssertThrowsError(try WebsiteSourceInference.infer(catalog: catalog, chapter: oversized, name: "x"))
    }
}
