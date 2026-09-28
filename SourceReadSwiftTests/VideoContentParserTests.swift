import XCTest
@testable import SourceReadSwift

final class VideoContentParserTests: XCTestCase {

    func testParseDirectHLSStream() {
        let chapter = BookChapter(title: "第1集", url: "https://example.com/play/1", bookUrl: "https://example.com/drama/1", index: 0, isVip: false)
        let text = "Here is the video stream: https://stream.example.com/hls/ep01.m3u8 and more text"
        let content = ChapterContent(chapter: chapter, title: "第1集", paragraphs: [text], nextContentUrl: nil)

        let parsed = VideoContentParser.parseVideoURL(from: content)
        XCTAssertEqual(parsed, "https://stream.example.com/hls/ep01.m3u8")
    }

    func testParseDirectMP4Stream() {
        let chapter = BookChapter(title: "第2集", url: "https://example.com/play/2", bookUrl: "https://example.com/drama/1", index: 1, isVip: false)
        let text = "Video link: https://video.example.com/episodes/ep02.mp4"
        let content = ChapterContent(chapter: chapter, title: "第2集", paragraphs: [text], nextContentUrl: nil)

        let parsed = VideoContentParser.parseVideoURL(from: content)
        XCTAssertEqual(parsed, "https://video.example.com/episodes/ep02.mp4")
    }

    func testParseHTMLVideoTag() {
        let chapter = BookChapter(title: "第3集", url: "https://example.com/play/3", bookUrl: "https://example.com/drama/1", index: 2, isVip: false)
        let html = """
        <div class="player-container">
            <video src="https://media.example.com/ep3.m3u8" controls autoplay></video>
        </div>
        """
        let content = ChapterContent(chapter: chapter, title: "第3集", paragraphs: [html], nextContentUrl: nil)

        let parsed = VideoContentParser.parseVideoURL(from: content)
        XCTAssertEqual(parsed, "https://media.example.com/ep3.m3u8")
    }

    func testParseHTMLSourceTag() {
        let chapter = BookChapter(title: "第4集", url: "https://example.com/play/4", bookUrl: "https://example.com/drama/1", index: 3, isVip: false)
        let html = """
        <video id="player">
            <source src="https://media.example.com/ep4.mp4" type="video/mp4" />
        </video>
        """
        let content = ChapterContent(chapter: chapter, title: "第4集", paragraphs: [html], nextContentUrl: nil)

        let parsed = VideoContentParser.parseVideoURL(from: content)
        XCTAssertEqual(parsed, "https://media.example.com/ep4.mp4")
    }

    func testParseJSONResponse() {
        let chapter = BookChapter(title: "第5集", url: "https://example.com/play/5", bookUrl: "https://example.com/drama/1", index: 4, isVip: false)
        let json = """
        {"code": 200, "url": "https://stream.example.com/live/ep05.m3u8", "type": "hls"}
        """
        let content = ChapterContent(chapter: chapter, title: "第5集", paragraphs: [json], nextContentUrl: nil)

        let parsed = VideoContentParser.parseVideoURL(from: content)
        XCTAssertEqual(parsed, "https://stream.example.com/live/ep05.m3u8")
    }

    func testParseFallbackChapterURL() {
        let chapter = BookChapter(title: "第6集", url: "https://cdn.example.com/direct/ep06.m3u8", bookUrl: "https://example.com/drama/1", index: 5, isVip: false)
        let emptyContent = ChapterContent(chapter: chapter, title: "第6集", paragraphs: [], nextContentUrl: nil)

        let parsed = VideoContentParser.parseVideoURL(from: emptyContent, chapterURL: chapter.url)
        XCTAssertEqual(parsed, "https://cdn.example.com/direct/ep06.m3u8")
    }
}
