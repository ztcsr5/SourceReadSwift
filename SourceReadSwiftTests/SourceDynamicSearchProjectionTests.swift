import XCTest
@testable import SourceReadSwift

final class SourceDynamicSearchProjectionTests: XCTestCase {
    func testManualVideoTypeProjectsOverStaleBookKindWithoutRewritingIt() {
        let url = "https://dynamic-search.invalid"
        let book = SearchBook(name: "预览", author: "作者", coverUrl: nil, bookUrl: url + "/1",
            sourceName: "Fixture", sourceUrl: url, mediaKind: .text)
        let video = DiscoverViewModel.makeProjection([book], kinds: [url: .video],
            kind: .video, query: "", scope: .all, userMediaKinds: [url: .video])
        XCTAssertEqual(video.results.map(\.mediaKind), [.video])
        XCTAssertEqual(video.aggregated.first?.id.mediaKind, .video)
        XCTAssertEqual(book.mediaKind, .text)
        let restored = DiscoverViewModel.makeProjection([book], kinds: [url: .text],
            kind: .video, query: "", scope: .all)
        XCTAssertTrue(restored.results.isEmpty)
    }
    func testJSONSearchKeepsDirectoryResolvedMediaCandidatesInEveryMediaFilter() throws {
        let source = dynamicSource()
        let books = try parse(source, body: #"{"items":[{"title":"待定作品","url":"/book/1"}]}"#)
        let book = try XCTUnwrap(books.first)
        XCTAssertTrue(source.hasDynamicMediaType)
        XCTAssertNil(book.mediaKind, "A source default is not evidence of this aggregate result's medium")
        for kind in [BookSourceKind.text, .comic, .audio, .video] {
            let projection = DiscoverViewModel.makeProjection(books, kinds: [source.bookSourceUrl: .text],
                kind: kind, query: "", scope: .all, dynamicSourceURLs: [source.bookSourceUrl])
            XCTAssertEqual(projection.results, books, "Do not discard a candidate before its directory decides its medium")
            XCTAssertNil(projection.results.first?.mediaKind, "Filtering must not persist the user's selected medium")
        }
    }

    func testHTMLSearchAlsoKeepsUnresolvedMediaUntilDirectoryParsing() throws {
        let source = BookSource(bookSourceName: "Mixed", bookSourceUrl: "https://dynamic-search.invalid",
            ruleSearch: .init(fields: ["bookList": "li", "name": "a@text", "bookUrl": "a@href"]),
            ruleToc: .init(fields: ["chapterUrl": "@js:book.type=64;result"]))
        let books = try parse(source, body: "<ul><li><a href='/book/1'>待定作品</a></li></ul>")
        XCTAssertEqual(books.count, 1)
        XCTAssertNil(books.first?.mediaKind)
        let projection = DiscoverViewModel.makeProjection(books, kinds: [source.bookSourceUrl: .text],
            kind: .comic, query: "待定", scope: .all, dynamicSourceURLs: [source.bookSourceUrl])
        XCTAssertEqual(projection.results, books)
    }

    func testExplicitTypesWinOverDynamicSourceAndDoNotLeakIntoTheFollowingRow() throws {
        let source = BookSource(bookSourceName: "Mixed", bookSourceUrl: "https://dynamic-search.invalid",
            ruleSearch: .init(fields: ["bookList": "$.items[*]", "name": "$.title",
                "bookUrl": "@js:if(result.media != null) book.type=result.media;result.url"]))
        let books = try parse(source, body: #"{"items":[{"title":"漫画","url":"/comic","media":64},{"title":"待定作品","url":"/unknown"},{"title":"小说","url":"/novel","media":8},{"title":"明确文本","url":"/text","media":0},{"title":"音频","url":"/audio","media":1}]}"#)
        XCTAssertEqual(books.map(\.mediaKind), [.comic, nil, .text, .text, .audio])
        let comics = DiscoverViewModel.makeProjection(books, kinds: [source.bookSourceUrl: .text],
            kind: .comic, query: "", scope: .all, dynamicSourceURLs: [source.bookSourceUrl])
        XCTAssertEqual(comics.results.map(\.name), ["漫画", "待定作品"])
        let audio = DiscoverViewModel.makeProjection(books, kinds: [source.bookSourceUrl: .text],
            kind: .audio, query: "", scope: .all, dynamicSourceURLs: [source.bookSourceUrl])
        XCTAssertEqual(audio.results.map(\.name), ["待定作品", "音频"])
    }

    func testLastSearchMetadataRuleCanStillResolveTheType() throws {
        let source = BookSource(bookSourceName: "Mixed", bookSourceUrl: "https://dynamic-search.invalid",
            ruleSearch: .init(fields: ["bookList": "$.items[*]", "name": "$.title", "bookUrl": "$.url",
                "checkKeyWord": "@js:book.type=32;'fixture'"]))
        let books = try parse(source, body: #"{"items":[{"title":"音频","url":"/audio"}]}"#)
        XCTAssertEqual(books.first?.mediaKind, .audio)
    }

    func testStaticSourceDefaultsAndLegacyRowsKeepTheirExistingTypeFilter() throws {
        for kind in [BookSourceKind.text, .comic, .audio, .video] {
            let source = BookSource(bookSourceName: "Static", bookSourceUrl: "https://static-search.invalid",
                bookSourceType: kind.rawValue,
                ruleSearch: .init(fields: ["bookList": "$.items[*]", "name": "$.title", "bookUrl": "$.url"]))
            let books = try parse(source, body: #"{"items":[{"title":"作品","url":"/book/1"}]}"#)
            XCTAssertEqual(books.first?.mediaKind, kind)
        }
        let legacy = SearchBook(name: "旧小说", author: nil, coverUrl: nil, bookUrl: "https://static-search.invalid/book/1",
            sourceName: "Static", sourceUrl: "https://static-search.invalid")
        let projection = DiscoverViewModel.makeProjection([legacy], kinds: [legacy.sourceUrl: .text],
            kind: .comic, query: "", scope: .all, dynamicSourceURLs: ["https://dynamic-search.invalid"])
        XCTAssertTrue(projection.results.isEmpty)
    }

    @MainActor
    func testStreamingProjectionAndRefilteringShareDynamicSourceMetadataAndInvalidateOnImport() async throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: location) }
        let sources = SourceStore(persistence: SourcePersistence(rootURL: location))
        let shelf = BookshelfStore(persistence: BookshelfPersistence(rootURL: location),
            groupPersistence: BookshelfGroupPersistence(rootURL: location))
        let source = dynamicSource()
        try sources.importSources([source])
        let state = AppState(sourceStore: sources, bookshelfStore: shelf)
        let model = state.discoverViewModel
        model.selectSourceKind(.comic)
        let books = try parse(source, body: #"{"items":[{"title":"待定作品","url":"/book/1"}]}"#)

        await model.installRankedResults(books)
        XCTAssertEqual(model.results, books)
        model.resultFilter = "待定"
        model.applyResultFilter()
        XCTAssertEqual(model.results, books)
        model.selectSourceKind(.audio)
        XCTAssertEqual(model.results, books)

        try sources.importSources([BookSource(bookSourceName: source.bookSourceName,
            bookSourceUrl: source.bookSourceUrl, ruleSearch: source.ruleSearch)])
        model.applyResultFilter()
        XCTAssertTrue(model.results.isEmpty, "Importing a static replacement must invalidate the dynamic-source cache")
        model.selectSourceKind(.text)
        XCTAssertEqual(model.results, books)
    }

    private func dynamicSource() -> BookSource {
        BookSource(bookSourceName: "Mixed", bookSourceUrl: "https://dynamic-search.invalid",
            ruleSearch: .init(fields: ["bookList": "$.items[*]", "name": "$.title", "bookUrl": "$.url"]),
            ruleToc: .init(fields: ["preUpdateJs": "book.type=64"]))
    }

    private func parse(_ source: BookSource, body: String) throws -> [SearchBook] {
        let response = SourceResponse(url: URL(string: "https://dynamic-search.invalid/search")!,
            statusCode: 200, headers: [:], body: body, data: Data(body.utf8))
        return try SearchResultParser().parse(source: source, response: response).get()
    }
}
