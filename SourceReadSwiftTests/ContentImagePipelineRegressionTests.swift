import XCTest
@testable import SourceReadSwift

final class ContentImagePipelineRegressionTests: XCTestCase {
    private let chapter = BookChapter(title: "第一话", url: "https://comic.example/chapter/1", bookUrl: "https://comic.example/book/1", index: 0, isVip: false)

    func testLazyOriginalWinsRegardlessOfAttributeOrder() {
        for tag in [
            #"<img data-original='/original.webp' src='/placeholder.png'>"#,
            #"<img src='data:image/gif;base64,AAAA' data-src='/original.webp'>"#,
            #"<amp-img data-lazy-src='/original.webp' src='/blank.png'></amp-img>"#
        ] {
            XCTAssertEqual(pages([tag]).map(\.url), ["https://comic.example/original.webp"])
        }
    }

    func testUnescapedLegadoImageHeaderOptionsSurviveHTML() throws {
        let tag = #"<img src="https://cdn.example/image?id=1&size=full,{"headers":{"Referer":"https://comic.example/reader","X-Image":"yes"}}">"#
        let page = try XCTUnwrap(pages([tag]).first)
        XCTAssertEqual(page.url, "https://cdn.example/image?id=1&size=full")
        XCTAssertEqual(page.headers["Referer"], "https://comic.example/reader")
        XCTAssertEqual(page.headers["X-Image"], "yes")
    }

    func testProductionContentNormalizationRetainsLazyPagesAndParagraphs() throws {
        let source = BookSource(bookSourceName: "Comic fixture", bookSourceUrl: "https://comic.example", ruleContent: SourceRule(fields: ["content": ".content@html"]))
        let html = #"<div class="content"><p>before</p><img src="/blank.png" data-src="/a.webp"><img data-original="//cdn.example/b.png?sig=a&amp;b=2"></div>"#
        let response = SourceResponse(url: URL(string: chapter.url)!, statusCode: 200, headers: [:], body: html, data: Data(html.utf8))
        let content = try ContentParser().parse(source: source, chapter: chapter, response: response).get()
        XCTAssertEqual(content.paragraphs.first, "before")
        let result = ComicContentParser.parsePages(from: content)
        XCTAssertEqual(result.map(\.url), ["https://comic.example/a.webp", "https://cdn.example/b.png?sig=a&b=2"])
    }

    func testExtensionlessURLsAndJSONArrayRemainUsable() {
        XCTAssertEqual(pages([#"["https://cdn.example/render?id=3","/p2.jpg"]"#]).map(\.url), ["https://cdn.example/render?id=3", "https://comic.example/p2.jpg"])
    }

    func testRejectsNavigationJavaScriptAndTrackingPlaceholders() {
        XCTAssertTrue(pages(["正文不是图片", "javascript:alert(1)", #"<img src="data:image/gif;base64,AAAA">"#]).isEmpty)
    }

    func testChapterRefererDefaultAndExplicitSourceHeaderPrecedence() {
        let source = BookSource(bookSourceName: "fixture", bookSourceUrl: "https://comic.example")
        XCTAssertEqual(SourceRequestBuilder().imageRequestHeaders(for: source, chapterURL: chapter.url)["Referer"], chapter.url)
        let configured = BookSource(bookSourceName: "fixture", bookSourceUrl: "https://comic.example", header: #"{"referer":"https://explicit.example/"}"#)
        let headers = SourceRequestBuilder().imageRequestHeaders(for: configured, chapterURL: chapter.url)
        XCTAssertEqual(headers["referer"], "https://explicit.example/")
        XCTAssertEqual(headers.keys.filter { $0.lowercased() == "referer" }.count, 1)
    }

    func testImageOptionsOverrideSourceHeadersCaseInsensitively() {
        let request = ComicImageRequest(url: "https://cdn.example/p.png", headers: ["Referer": "https://image.example/"])
        let result = request.mergingHeaders(["referer": "https://source.example/", "User-Agent": "fixture"], chapterURL: chapter.url)
        XCTAssertEqual(result["Referer"], "https://image.example/")
        XCTAssertNil(result["referer"])
        XCTAssertEqual(result["User-Agent"], "fixture")
    }

    private func pages(_ paragraphs: [String]) -> [ComicPage] {
        ComicContentParser.parsePages(from: ChapterContent(chapter: chapter, title: chapter.title, paragraphs: paragraphs, nextContentUrl: nil))
    }
}
