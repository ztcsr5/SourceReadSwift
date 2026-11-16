import XCTest
@testable import SourceReadSwift

final class BookDetailMediaRoutingTests: XCTestCase {
    func testSelectedVideoChapterOverridesEarlierComicAndBookDefault() throws {
        let source = BookSource(bookSourceName: "Mixed", bookSourceUrl: "https://media-route.invalid",
            ruleToc: .init(fields: ["chapterList": "$.chapters[*]", "chapterName": "$.title",
                "chapterUrl": "@js:book.type=result.media;result.url"]))
        let book = BookDetail(name: "Mixed work", author: nil, coverUrl: nil,
            bookUrl: "https://media-route.invalid/book", sourceName: source.bookSourceName,
            sourceUrl: source.bookSourceUrl, intro: nil, latestChapter: nil, mediaKind: .comic)
        let body = #"{"chapters":[{"title":"漫画","url":"/comic","media":64},{"title":"视频","url":"/video","media":4}]}"#
        let response = SourceResponse(url: URL(string: "https://media-route.invalid/toc")!,
            statusCode: 200, headers: [:], body: body, data: Data(body.utf8))
        let chapters = try ChapterListParser().parse(source: source, book: book, response: response).get()
        let selectedSource = BookDetailView.resolveChapterSource(source, chapters: chapters,
            chapterIndex: 1, fallbackMediaKind: book.mediaKind)
        XCTAssertEqual(chapters.map(\.mediaKind), [.comic, .video])
        XCTAssertEqual(selectedSource.sourceKind, .video)
        XCTAssertEqual(source.sourceKind, .text, "Selecting a chapter must not reclassify the whole source")
    }

    func testSelectedChapterUsesItsIdentityRatherThanArrayOffset() {
        let source = BookSource(bookSourceName: "Mixed", bookSourceUrl: "https://media-route.invalid")
        let chapters = [chapter(index: 9, kind: .comic), chapter(index: 42, kind: .video)]
        let selectedSource = BookDetailView.resolveChapterSource(source, chapters: chapters,
            chapterIndex: 42, fallbackMediaKind: .comic)
        XCTAssertEqual(selectedSource.sourceKind, .video)
    }

    func testAllChapterSelectionDoesNotForceNonComicEntriesIntoComicReader() {
        let source = BookSource(bookSourceName: "Mixed", bookSourceUrl: "https://media-route.invalid")
        for kind in [BookSourceKind.text, .audio, .comic, .video] {
            let chapters = [chapter(index: 0, kind: .comic), chapter(index: 1, kind: kind)]
            let selectedSource = BookDetailView.resolveChapterSource(source, chapters: chapters,
                chapterIndex: 1, fallbackMediaKind: .comic)
            XCTAssertEqual(selectedSource.sourceKind, kind)
            XCTAssertEqual(selectedSource.sourceKind == .comic, kind == .comic)
        }
    }

    func testUnknownOrMissingSelectedChapterFallsBackToBookThenSource() {
        let source = BookSource(bookSourceName: "Audio", bookSourceUrl: "https://media-route.invalid", bookSourceType: 1)
        let chapters = [chapter(index: 0, kind: nil)]
        XCTAssertEqual(BookDetailView.resolveChapterSource(source, chapters: chapters,
            chapterIndex: 0, fallbackMediaKind: .video).sourceKind, .video)
        XCTAssertEqual(BookDetailView.resolveChapterSource(source, chapters: chapters,
            chapterIndex: 99, fallbackMediaKind: .comic).sourceKind, .comic)
        XCTAssertEqual(BookDetailView.resolveChapterSource(source, chapters: chapters,
            chapterIndex: 0, fallbackMediaKind: nil).sourceKind, .audio)
    }

    private func chapter(index: Int, kind: BookSourceKind?) -> BookChapter {
        BookChapter(title: "Entry", url: "https://media-route.invalid/chapter/\(index)",
            bookUrl: "https://media-route.invalid/book", index: index, mediaKind: kind)
    }
}
