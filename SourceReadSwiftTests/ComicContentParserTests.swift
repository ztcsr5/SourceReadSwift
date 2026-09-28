import XCTest
@testable import SourceReadSwift

final class ComicContentParserTests: XCTestCase {

    func testParseImgTokensInParagraphs() {
        let chapter = BookChapter(title: "第1话", url: "https://example.com/c1", bookUrl: "https://example.com/b1", index: 0, isVip: false)
        let paragraphs = [
            "[img]https://img.example.com/page1.jpg[/img]",
            "[img]https://img.example.com/page2.png[/img]",
            "[img]https://img.example.com/page3.webp[/img]"
        ]
        let content = ChapterContent(chapter: chapter, title: "第1话", paragraphs: paragraphs, nextContentUrl: nil)
        let pages = ComicContentParser.parsePages(from: content)

        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(pages[0].id, 0)
        XCTAssertEqual(pages[0].url, "https://img.example.com/page1.jpg")
        XCTAssertEqual(pages[1].id, 1)
        XCTAssertEqual(pages[1].url, "https://img.example.com/page2.png")
        XCTAssertEqual(pages[2].id, 2)
        XCTAssertEqual(pages[2].url, "https://img.example.com/page3.webp")
    }

    func testParsePlainImageURLs() {
        let chapter = BookChapter(title: "第2话", url: "https://example.com/c2", bookUrl: "https://example.com/b1", index: 1, isVip: false)
        let paragraphs = [
            "https://img.example.com/001.jpg",
            "https://img.example.com/002.jpg"
        ]
        let content = ChapterContent(chapter: chapter, title: "第2话", paragraphs: paragraphs, nextContentUrl: nil)
        let pages = ComicContentParser.parsePages(from: content)

        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].url, "https://img.example.com/001.jpg")
        XCTAssertEqual(pages[1].url, "https://img.example.com/002.jpg")
    }

    func testParseHTMLImgTags() {
        let chapter = BookChapter(title: "第3话", url: "https://example.com/c3", bookUrl: "https://example.com/b1", index: 2, isVip: false)
        let html = """
        <div class="comic-wrap">
            <img src="https://cdn.example.com/manga/p1.jpeg" alt="p1" />
            <img data-src="https://cdn.example.com/manga/p2.jpeg" alt="p2" />
            <img data-original="https://cdn.example.com/manga/p3.jpeg" alt="p3" />
        </div>
        """
        let content = ChapterContent(chapter: chapter, title: "第3话", paragraphs: [html], nextContentUrl: nil)
        let pages = ComicContentParser.parsePages(from: content)

        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(pages[0].url, "https://cdn.example.com/manga/p1.jpeg")
        XCTAssertEqual(pages[1].url, "https://cdn.example.com/manga/p2.jpeg")
        XCTAssertEqual(pages[2].url, "https://cdn.example.com/manga/p3.jpeg")
    }

    func testParseJSONArray() {
        let chapter = BookChapter(title: "第4话", url: "https://example.com/c4", bookUrl: "https://example.com/b1", index: 3, isVip: false)
        let json = "[\"https://cdn.example.com/p1.jpg\", \"https://cdn.example.com/p2.jpg\"]"
        let content = ChapterContent(chapter: chapter, title: "第4话", paragraphs: [json], nextContentUrl: nil)
        let pages = ComicContentParser.parsePages(from: content)

        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].url, "https://cdn.example.com/p1.jpg")
        XCTAssertEqual(pages[1].url, "https://cdn.example.com/p2.jpg")
    }

    func testDeduplication() {
        let chapter = BookChapter(title: "第5话", url: "https://example.com/c5", bookUrl: "https://example.com/b1", index: 4, isVip: false)
        let paragraphs = [
            "[img]https://img.example.com/page1.jpg[/img]",
            "[img]https://img.example.com/page1.jpg[/img]",
            "[img]https://img.example.com/page2.jpg[/img]"
        ]
        let content = ChapterContent(chapter: chapter, title: "第5话", paragraphs: paragraphs, nextContentUrl: nil)
        let pages = ComicContentParser.parsePages(from: content)

        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].url, "https://img.example.com/page1.jpg")
        XCTAssertEqual(pages[1].url, "https://img.example.com/page2.jpg")
    }
}
