import XCTest
@testable import SourceReadSwift

final class MediaBookDirectoryTests: XCTestCase {
    func testLegadoVideoAndDownloadSourceNumbersDoNotEnterTheWrongMediaFilter() throws {
        let imported = #"{"bookSourceName":"影片","bookSourceUrl":"https://movie.invalid","bookSourceType":4}"#
        let video = try JSONDecoder().decode(BookSource.self, from: Data(imported.utf8))
        XCTAssertEqual(video.bookSourceType, 4)
        XCTAssertEqual(video.resolvingMediaKind(.text).sourceKind, .video)
        XCTAssertTrue(video.canSearch(mediaKind: .video))
        let legacy = BookSource(bookSourceName: "Legacy video", bookSourceUrl: "https://legacy.invalid", bookSourceType: 3)
        XCTAssertEqual(legacy.sourceKind, .video)
        let file = BookSource(bookSourceName: "Archive", bookSourceUrl: "https://archive.invalid", bookSourceType: 3,
            ruleBookInfo: .init(fields: ["downloadUrls": ".download@href"]))
        XCTAssertFalse(file.canSearch(mediaKind: .video))
        XCTAssertTrue(file.displayBadges.contains("文件"))
        let music = BookSource(bookSourceName: "音乐样本", bookSourceUrl: "https://music.invalid", bookSourceType: 1)
        XCTAssertTrue(music.canSearch(mediaKind: .audio))
        XCTAssertTrue(music.displayBadges.contains("音乐"))
    }

    func testVideoNumberWithExplicitComicPageRuleSearchesAndParsesAsComic() throws {
        let exported = #"{"bookSourceName":"样本","bookSourceUrl":"https://comic.invalid","bookSourceType":4,"ruleContent":{"content":"$.imageList"}}"#
        let source = try JSONDecoder().decode(BookSource.self, from: Data(exported.utf8))
        XCTAssertEqual(source.bookSourceType, 4, "Keep the author's original JSON declaration")
        XCTAssertTrue(source.canSearch(mediaKind: .comic))
        XCTAssertFalse(source.canSearch(mediaKind: .video))
        XCTAssertEqual(source.resolvingMediaKind(.video).sourceKind, .comic, "Discard an older inferred shelf kind")
        let chapter = BookChapter(title: "第一话", url: "https://comic.invalid/read/1", bookUrl: "https://comic.invalid/book/1", index: 0)
        let pageList = response(#"{"imageList":["/first.jpg","/second.webp"]}"#,
                                url: chapter.url, headers: ["Content-Type": "application/json"])
        let content = try ContentParser().parse(source: source, chapter: chapter, response: pageList).get()
        XCTAssertEqual(ComicContentParser.parsePages(from: content).map(\.url),
                       ["https://comic.invalid/first.jpg", "https://comic.invalid/second.webp"])
    }

    func testComicNumberWithExplicitVideoRuleUsesStreamingDirectory() {
        let source = BookSource(bookSourceName: "样本", bookSourceUrl: "https://media.invalid",
                                bookSourceType: 2, ruleContent: .init(fields: ["content": "video@src"]))
        XCTAssertTrue(source.canSearch(mediaKind: .video))
        XCTAssertFalse(source.canSearch(mediaKind: .comic))
        XCTAssertEqual(source.resolvingMediaKind(.comic).sourceKind, .video)
    }

    func testAmbiguousMediaRulesAndExplicitPerBookKindsAreNotReclassified() {
        let contentRule = SourceRule(fields: ["content": "$.imageList || $.videoUrl"])
        let ambiguous = BookSource(bookSourceName: "漫画", bookSourceUrl: "https://mixed.invalid",
                                   bookSourceType: 4, ruleContent: contentRule)
        XCTAssertEqual(ambiguous.sourceKind, .video)
        let mixed = BookSource(bookSourceName: "混合", bookSourceUrl: "https://mixed.invalid",
                               bookSourceType: 4, ruleSearch: .init(fields: ["bookUrl": "@js:book.type=64;result"]),
                               ruleContent: .init(fields: ["content": "$.imageList"]))
        XCTAssertEqual(mixed.sourceKind, .video)
        XCTAssertEqual(mixed.resolvingMediaKind(.comic).sourceKind, .comic)
        XCTAssertEqual(mixed.resolvingMediaKind(.comic).resolvingMediaKind(.video).sourceKind, .video)
    }

    func testSeparateDirectoryWaitsForTheDetailRuleInsteadOfProbingTheWrongPage() {
        let source = BookSource(bookSourceName: "Separate", bookSourceUrl: "https://catalog.invalid",
                                ruleBookInfo: .init(fields: ["chapterListUrl": "$.directory"]))
        XCTAssertTrue(BookDetailDirectoryPolicy.waitsForDetail(source))
        XCTAssertFalse(BookDetailDirectoryPolicy.waitsForDetail(fixtureSource(kind: 2)))
    }

    func testResolvedDirectoryOverridesAnAlreadySuccessfulGuessOnlyWhenItsTargetChanges() {
        let source = fixtureSource(kind: 2)
        let placeholder = book(source)
        let resolved = BookDetail(name: placeholder.name, author: nil, coverUrl: nil,
                                  bookUrl: placeholder.bookUrl, tocUrl: "https://music.invalid/chapters",
                                  sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl,
                                  intro: nil, latestChapter: nil)
        XCTAssertTrue(BookDetailDirectoryPolicy.destinationChanged(from: placeholder, to: resolved, source: source))
        XCTAssertFalse(BookDetailDirectoryPolicy.destinationChanged(from: placeholder, to: placeholder, source: source))
    }

    func testSingleTrackWithoutChapterURLRunsContentRulesOnTheDirectoryPage() throws {
        let source = fixtureSource(kind: 1)
        let page = response("<h1 class='view_tit'>青山</h1><audio src='/track.mp3'></audio>")
        let chapters = try ChapterListParser().parse(source: source, book: book(source), response: page).get()
        XCTAssertEqual(chapters.map(\.title), ["青山"])
        XCTAssertEqual(chapters.map(\.url), [page.url.absoluteString])
        let chapter = try XCTUnwrap(chapters.first)
        let content = try ContentParser().parse(source: source, chapter: chapter, response: page).get()
        XCTAssertEqual(AudioContentParser.parseURL(content.text, base: chapter.url), "https://music.invalid/track.mp3")

        let novel = fixtureSource(kind: 0)
        if case .success = ChapterListParser().parse(source: novel, book: book(novel), response: page) {
            XCTFail("Text sources must not get a synthetic chapter")
        }
        let ambiguous = response("<h1 class='view_tit'>第一首</h1><h1 class='view_tit'>第二首</h1>")
        if case .success = ChapterListParser().parse(source: source, book: book(source), response: ambiguous) {
            XCTFail("Tracks without distinct URLs must not all point to a single page")
        }
    }

    func testChapterResponseCanBeAnExtensionlessAudioStreamOrPlaylist() throws {
        let source = BookSource(bookSourceName: "Music", bookSourceUrl: "https://music.invalid", bookSourceType: 1)
        let chapter = BookChapter(title: "Track", url: "https://music.invalid/album/play?sig=fixture",
                                  bookUrl: book(source).bookUrl, index: 0)
        let audio = try ContentParser().parse(source: source, chapter: chapter,
            response: response("", url: chapter.url, headers: ["Content-Type": "audio/mpeg"])).get()
        XCTAssertEqual(audio.paragraphs, [chapter.url])
        let video = "https://music.invalid/episode/index.m3u8?sig=fixture"
        let directive = #",{"headers":{"Referer":"https://music.invalid/"}}"#
        XCTAssertEqual(VideoContentParser.directPlaybackURL(video + directive, base: chapter.url), video + directive)
        XCTAssertNil(VideoContentParser.directPlaybackURL("https://music.invalid/watch", base: chapter.url))
    }

    private func fixtureSource(kind: Int) -> BookSource {
        BookSource(bookSourceName: "音乐", bookSourceUrl: "https://music.invalid", bookSourceType: kind,
                   ruleToc: .init(fields: ["chapterList": ".view_tit", "chapterName": "text"]),
                   ruleContent: .init(fields: ["content": "audio@src"]))
    }

    private func book(_ source: BookSource) -> BookDetail {
        BookDetail(name: "样本", author: nil, coverUrl: nil, bookUrl: "https://music.invalid/album",
                   sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil, latestChapter: nil)
    }

    private func response(_ body: String, url: String = "https://music.invalid/album",
                          headers: [String: String] = [:]) -> SourceResponse {
        SourceResponse(url: URL(string: url)!, statusCode: 200, headers: headers, body: body, data: Data(body.utf8))
    }
}
