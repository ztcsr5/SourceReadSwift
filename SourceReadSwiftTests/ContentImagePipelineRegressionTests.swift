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

    func testLiteralBackslashImageDelimitersFromSourceJavaScript() throws {
        let tag = #"<img src=\"https://cdn.example/a.webp,{"headers":{"Referer":"https://comic.example/reader"}}\">"#
        let page = try XCTUnwrap(pages([tag]).first)
        XCTAssertEqual(page.url, "https://cdn.example/a.webp")
        XCTAssertEqual(page.headers["Referer"], "https://comic.example/reader")
    }

    func testCSSNodesCanBecomeObjectDirectoryThroughJavaScript() throws {
        let source = BookSource(bookSourceName: "CSS JS fixture", bookSourceUrl: "https://comic.example", ruleToc: SourceRule(fields: [
            "chapterList": ".chapter@js:Array.from(result).map(n => ({text:n.text(),href:n.attr('href')}))",
            "chapterName": "text", "chapterUrl": "href"
        ]))
        let book = BookDetail(name: "fixture", author: nil, coverUrl: nil, bookUrl: "https://comic.example/book/1", sourceName: "fixture", sourceUrl: source.bookSourceUrl, intro: nil, latestChapter: nil)
        let html = #"<a class="chapter" href="/c1">第一话</a><a class="chapter" href="/c2">第二话</a>"#
        let response = SourceResponse(url: URL(string: book.bookUrl)!, statusCode: 200, headers: [:], body: html, data: Data(html.utf8))
        let chapters = try ChapterListParser().parse(source: source, book: book, response: response).get()
        XCTAssertEqual(chapters.map(\.title), ["第一话", "第二话"])
        XCTAssertEqual(chapters.map(\.url), ["https://comic.example/c1", "https://comic.example/c2"])
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

    func testExtractedImageArraySplitsOnNewlinesWithoutJoiningURLsWithCommas() throws {
        let rule = #"data.pages@js:result.split("\n").map(x => '<img src=\"' + x + ',{"headers":{"Referer":"https://comic.example/reader"}}\">').join("\n")"#
        let source = BookSource(bookSourceName: "Array image fixture", bookSourceUrl: "https://comic.example", ruleContent: SourceRule(fields: ["content": rule]))
        let body = #"{"data":{"pages":["https://cdn.example/a.jpg","https://cdn.example/b.jpg"]}}"#
        let response = SourceResponse(url: URL(string: chapter.url)!, statusCode: 200, headers: ["Content-Type": "application/json"], body: body, data: Data(body.utf8))
        let content = try ContentParser().parse(source: source, chapter: chapter, response: response).get()
        let result = ComicContentParser.parsePages(from: content)
        XCTAssertEqual(result.map(\.url), ["https://cdn.example/a.jpg", "https://cdn.example/b.jpg"])
        XCTAssertEqual(result.map { $0.headers["Referer"] }, ["https://comic.example/reader", "https://comic.example/reader"])
    }

    func testDirectImageChapterUsesResponseURLInsteadOfTextRules() throws {
        let source = BookSource(bookSourceName: "Image chapter fixture", bookSourceUrl: "https://comic.example", bookSourceType: 2, ruleContent: SourceRule(fields: ["content": "@get:{img}"]))
        let url = URL(string: "https://cdn.example/direct.png")!
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aDZkAAAAASUVORK5CYII=")!
        let response = SourceResponse(url: url, statusCode: 200, headers: ["content-type": "image/png"], body: "", data: data)
        let content = try ContentParser().parse(source: source, chapter: chapter, response: response).get()
        XCTAssertEqual(ComicContentParser.parsePages(from: content).map(\.url), [url.absoluteString])
        XCTAssertEqual(content.title, chapter.title)
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
