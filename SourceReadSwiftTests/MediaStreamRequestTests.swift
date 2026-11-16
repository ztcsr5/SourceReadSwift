import XCTest
@testable import SourceReadSwift

final class MediaStreamRequestTests: XCTestCase {
    private let episode = BookChapter(title: "第3集", url: "https://media.fixture.invalid/watch/3",
        bookUrl: "https://media.fixture.invalid/book", index: 8)

    func testPlainAudioAndVideoDirectivesSurviveSpacesAndSignedQueries() throws {
        for extensionName in ["mp3", "m3u8"] {
            let reference = "https://cdn.fixture.invalid/episode.\(extensionName)?sign=a%2Bb,{\"headers\": {\"Referer\": \"https://media.fixture.invalid/\"}}"
            let content = ChapterContent(chapter: episode, title: episode.title, paragraphs: [reference])
            let resolved = extensionName == "mp3" ? AudioContentParser.parseURL(reference, base: episode.url)
                : VideoContentParser.parseVideoURL(from: content)
            XCTAssertEqual(resolved, reference)
            let source = BookSource(bookSourceName: "播放样本", bookSourceUrl: "https://media.fixture.invalid")
            let request = try XCTUnwrap(MediaStreamRequest(try XCTUnwrap(resolved), source: source, episode: episode))
            XCTAssertEqual(request.url.query, "sign=a%2Bb")
            XCTAssertEqual(request.headers["Referer"], "https://media.fixture.invalid/")
        }
    }

    func testDirectiveOverridesHeadersWithoutDuplicatingTheirCasing() throws {
        let source = BookSource(bookSourceName: "播放样本", bookSourceUrl: "https://media.fixture.invalid")
        let reference = "../track.mp3,{\"headers\":{\"referer\":\"https://reader.fixture.invalid/\",\"Host\":\"wrong.invalid\",\"X-Bad\":\"a\\r\\nb\"}}"
        let request = try XCTUnwrap(MediaStreamRequest(reference, source: source, episode: episode))
        XCTAssertEqual(request.url.absoluteString, "https://media.fixture.invalid/track.mp3")
        XCTAssertEqual(request.headers.filter { $0.key.lowercased() == "referer" }.count, 1)
        XCTAssertEqual(request.headers["referer"], "https://reader.fixture.invalid/")
        XCTAssertNil(request.headers["Host"])
        XCTAssertNil(request.headers["X-Bad"])
    }

    func testInvalidSchemesAndEmbeddedCredentialsDoNotReachThePlayer() {
        let source = BookSource(bookSourceName: "播放样本", bookSourceUrl: "https://media.fixture.invalid")
        for reference in ["file:///private/track.mp3", "javascript:alert(1)", "https://user:password@media.fixture.invalid/track.mp3"] {
            XCTAssertNil(MediaStreamRequest(reference, source: source, episode: episode))
        }
    }
}
