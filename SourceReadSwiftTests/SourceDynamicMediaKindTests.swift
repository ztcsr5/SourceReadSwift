import XCTest
@testable import SourceReadSwift

final class SourceDynamicMediaKindTests: XCTestCase {
    func testDirectoryTypeWritersParticipateInMediaSearchWithoutReclassifyingTheSource() {
        for field in ["preUpdateJs", "init", "chapterList", "chapterUrl"] {
            let source = BookSource(bookSourceName: "Mixed", bookSourceUrl: "https://media.fixture.invalid",
                ruleToc: .init(fields: [field: "@js:book.type = 64; result"]))
            XCTAssertTrue(source.hasDynamicMediaType, field)
            XCTAssertTrue(source.canSearch(mediaKind: .comic), field)
            XCTAssertTrue(source.canSearch(mediaKind: .audio), field)
            XCTAssertEqual(source.sourceKind, .text, "A potential type write does not select a medium")
        }
    }

    func testContentTypeWriterAndRawRulesAreDetected() {
        let content = BookSource(bookSourceName: "Mixed", bookSourceUrl: "https://media.fixture.invalid",
            ruleContent: .init(fields: ["content": "@js:book.setType(32); result"]))
        XCTAssertTrue(content.canSearch(mediaKind: .audio))
        let raw = BookSource(bookSourceName: "Raw", bookSourceUrl: "https://media.fixture.invalid/raw",
            ruleToc: .init(raw: "@js:book.type = 64; result"))
        XCTAssertTrue(raw.hasDynamicMediaType)
    }

    func testLegadoMediaFlagsIgnoreAuxiliaryBitsWithoutChangingStoredRawValues() {
        XCTAssertEqual(BookSourceKind(legadoBookType: 136), .text)
        XCTAssertEqual(BookSourceKind(legadoBookType: 32 | 128), .audio)
        XCTAssertEqual(BookSourceKind(legadoBookType: 64 | 128), .comic)
        XCTAssertEqual(BookSourceKind(legadoBookType: 4 | 128), .video)
        XCTAssertNil(BookSourceKind(legadoBookType: 8 | 64), "Conflicting media flags must remain unresolved")
        XCTAssertNil(BookSourceKind(legadoBookType: -1))
        for value in [0, 1, 2, 3, 128] { XCTAssertNil(BookSourceKind(legadoBookType: value)) }
        XCTAssertEqual(BookSourceKind(rawValue: 0), .text)
        XCTAssertEqual(BookSourceKind(rawValue: 1), .audio)
        XCTAssertEqual(BookSourceKind(rawValue: 2), .comic)
        XCTAssertEqual(BookSourceKind(rawValue: 3), .video)
    }

    func testExplicitIOSBookTypesAreSeparateFromUnspecifiedTypeAndLegadoFlags() throws {
        let book = SearchBook(name: "Fixture", author: nil, coverUrl: nil,
            bookUrl: "https://media.fixture.invalid/book/1", sourceName: "Mixed", sourceUrl: "https://media.fixture.invalid")
        let bridge = LegadoSearchBookBridge(book: book)
        XCTAssertNil(bridge.mediaKind, "An unspecified zero must not override the source type")
        bridge.initializeMediaKindIfNeeded(.audio)
        XCTAssertEqual(bridge.mediaKind, .audio)
        XCTAssertFalse(bridge.hasExplicitType)
        bridge.type = 0
        XCTAssertEqual(bridge.mediaKind, .text)
        let runtime = JSCoreRuntime()
        XCTAssertEqual(try runtime.evaluate("book.setType(1); book.getType()", variables: ["book": bridge]).get(), "1")
        XCTAssertEqual(bridge.mediaKind, .audio)
        bridge.type = 2
        XCTAssertEqual(bridge.mediaKind, .comic)
        bridge.type = 3
        XCTAssertEqual(bridge.mediaKind, .video)
        bridge.type = 136
        XCTAssertEqual(bridge.mediaKind, .text)
        XCTAssertEqual(bridge.getType(), 136, "Keep the author's value visible to JS")
    }

    func testJSONDirectoryListTypeSurvivesTheFollowingFieldRules() throws {
        let source = source(toc: [
            "chapterList": #"@js:book.type=64; [{title:'第一话',url:'/chapter/1'},{title:'第二话',url:'/chapter/2'}]"#,
            "chapterName": "@js:String(book.type) + ':' + result.title",
            "chapterUrl": "$.url"
        ])
        let chapters = try parse(source, body: "{}").get()
        XCTAssertEqual(chapters.map(\.title), ["64:第一话", "64:第二话"])
        XCTAssertEqual(chapters.map(\.mediaKind), [.comic, .comic])
        XCTAssertEqual(source.sourceKind, .text)
    }

    func testJSONDirectoryURLTypeIsKeptPerChapter() throws {
        let source = source(toc: ["chapterList": "$.chapters[*]", "chapterName": "$.title",
            "chapterUrl": "@js:book.type=result.media;result.url"])
        let chapters = try parse(source, body: #"{"chapters":[{"title":"第一话","url":"/chapter/1","media":64},{"title":"朗读","url":"/chapter/2","media":32}]}"#).get()
        XCTAssertEqual(chapters.map(\.mediaKind), [.comic, .audio])
        XCTAssertEqual(chapters.map(\.url), ["https://media.fixture.invalid/chapter/1", "https://media.fixture.invalid/chapter/2"])
    }

    func testIOSAggregateTypeAssignmentsRouteAudioComicAndVideo() throws {
        let source = source(toc: ["chapterList": "$.chapters[*]", "chapterName": "$.title",
            "chapterUrl": "@js:book.type=result.media;result.url"])
        let chapters = try parse(source, body: #"{"chapters":[{"title":"文本","url":"/chapter/0","media":0},{"title":"音频","url":"/chapter/1","media":1},{"title":"漫画","url":"/chapter/2","media":2},{"title":"视频","url":"/chapter/3","media":3}]}"#).get()
        XCTAssertEqual(chapters.map(\.mediaKind), [.text, .audio, .comic, .video])
    }

    func testHTMLDirectoryURLTypeSurvivesMetadataAndReindexing() throws {
        let source = source(toc: ["chapterList": "li", "chapterName": "a@text",
            "chapterUrl": "a@href@js:book.type=64;result", "updateTime": "@js:String(book.type)"])
        let chapters = try parse(source, body: "<ul><li><a href='/chapter/1'>第一话</a></li></ul>").get()
        let chapter = try XCTUnwrap(chapters.first)
        XCTAssertEqual(chapter.mediaKind, .comic)
        XCTAssertEqual(chapter.updateTime, "64")
        XCTAssertEqual(chapter.withIndex(3).withTitle("更新标题").mediaKind, .comic)
    }

    func testChapterMediaKindPersistsAndOldDirectoryCachesRemainReadable() throws {
        let legacy = #"{"title":"旧章","url":"https://media.fixture.invalid/chapter/1","bookUrl":"https://media.fixture.invalid/book/1","index":0,"isVip":false}"#
        let old = try JSONDecoder().decode(BookChapter.self, from: Data(legacy.utf8))
        XCTAssertNil(old.mediaKind)
        let chapter = BookChapter(title: old.title, url: old.url, bookUrl: old.bookUrl, index: old.index, mediaKind: .comic)
        let restored = try JSONDecoder().decode(BookChapter.self, from: JSONEncoder().encode(chapter))
        XCTAssertEqual(restored.mediaKind, .comic)
        XCTAssertEqual(restored.withIndex(12).withTitle("重命名").mediaKind, .comic)
    }

    func testOrdinaryChaptersDoNotAcquireAnUnnecessaryMediaOverride() throws {
        let source = source(toc: ["chapterList": "li", "chapterName": "a@text", "chapterUrl": "a@href"])
        let chapters = try parse(source, body: "<ul><li><a href='/chapter/1'>第一章</a></li></ul>").get()
        XCTAssertEqual(chapters, [BookChapter(title: "第一章", url: "https://media.fixture.invalid/chapter/1",
            bookUrl: "https://media.fixture.invalid/book/1", index: 0)])
    }

    func testDirectoryTypeSurvivesNextPageButDoesNotLeakToAnotherBook() throws {
        let source = source(toc: [
            "chapterList": "@js:if(body.indexOf('switchToComic')>=0) book.type=64; [{title:'chapter',url:'/chapter/1'}]",
            "chapterName": "$.title", "chapterUrl": "$.url"
        ])
        let parser = ChapterListParser()
        func load(bookURL: String, body: String) throws -> BookChapter {
            let book = BookDetail(name: "Fixture", author: nil, coverUrl: nil, bookUrl: bookURL,
                sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil, latestChapter: nil)
            let response = SourceResponse(url: URL(string: "https://media.fixture.invalid/toc/1")!,
                statusCode: 200, headers: [:], body: body, data: Data(body.utf8))
            return try XCTUnwrap(parser.parsePage(source: source, book: book, response: response).get().chapters.first)
        }
        XCTAssertEqual(try load(bookURL: "https://media.fixture.invalid/book/1", body: "switchToComic").mediaKind, .comic)
        XCTAssertEqual(try load(bookURL: "https://media.fixture.invalid/book/1", body: "nextPage").mediaKind, .comic)
        XCTAssertNil(try load(bookURL: "https://media.fixture.invalid/book/2", body: "nextPage").mediaKind)
    }

    func testPreUpdateTypeReachesDirectoryURLBodyHookAndAllPages() async throws {
        let source = source(toc: [
            "preUpdateJs": "book.setType(64)",
            "bodyJs": "if(book.type!==64) throw new Error('lost TOC type'); result",
            "chapterList": "$.chapters[*]", "chapterName": "@js:String(book.type)+':'+result.title",
            "chapterUrl": "$.url", "nextTocUrl": "$.next"
        ])
        let network = DynamicMediaDirectoryNetwork()
        let engine = LegadoSourceEngine(network: network, cookieStore: SourceCookieStore(storageURL: nil))
        let book = BookDetail(name: "Fixture", author: nil, coverUrl: nil,
            bookUrl: "https://media.fixture.invalid/book/1",
            tocUrl: "@js:'https://media.fixture.invalid/toc/'+book.type",
            sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil, latestChapter: nil)
        let chapters = try await engine.getChapterList(source: source, book: book, maxPages: 2).get()
        XCTAssertEqual(chapters.map(\.mediaKind), [.comic, .comic])
        XCTAssertEqual(chapters.map(\.title), ["64:first", "64:second"])
        XCTAssertEqual(chapters.map(\.index), [0, 1])
        let requests = await network.paths
        XCTAssertEqual(requests, ["/toc/64", "/toc/next"])
    }

    func testExplicitTextTypeDoesNotInheritThePreviousComicChapter() throws {
        let source = source(toc: ["chapterList": "$.chapters[*]", "chapterName": "$.title",
            "chapterUrl": "@js:book.type=result.media;result.url"])
        let chapters = try parse(source, body: #"{"chapters":[{"title":"漫画","url":"/chapter/1","media":64},{"title":"文本","url":"/chapter/2","media":8}]}"#).get()
        XCTAssertEqual(chapters.map(\.mediaKind), [.comic, .text])
    }

    private func source(toc: [String: String]) -> BookSource {
        BookSource(bookSourceName: "Mixed", bookSourceUrl: "https://media.fixture.invalid", ruleToc: .init(fields: toc))
    }

    private func parse(_ source: BookSource, body: String) -> Result<[BookChapter], SourceEngineError> {
        let book = BookDetail(name: "Fixture", author: nil, coverUrl: nil,
            bookUrl: "https://media.fixture.invalid/book/1", sourceName: source.bookSourceName,
            sourceUrl: source.bookSourceUrl, intro: nil, latestChapter: nil)
        let response = SourceResponse(url: URL(string: "https://media.fixture.invalid/toc/1")!,
            statusCode: 200, headers: [:], body: body, data: Data(body.utf8))
        return ChapterListParser().parse(source: source, book: book, response: response)
    }
}

private actor DynamicMediaDirectoryNetwork: SourceNetworkClient {
    private(set) var paths: [String] = []

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        paths.append(request.url.path)
        let body: String
        switch request.url.path {
        case "/toc/64": body = #"{"chapters":[{"title":"first","url":"/chapter/1"}],"next":"https://media.fixture.invalid/toc/next"}"#
        case "/toc/next": body = #"{"chapters":[{"title":"second","url":"/chapter/2"}]}"#
        default: return .failure(.network("Unexpected directory request"))
        }
        return .success(SourceResponse(url: request.url, statusCode: 200,
            headers: ["Content-Type": "application/json"], body: body, data: Data(body.utf8)))
    }
}
