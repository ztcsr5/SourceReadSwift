import Foundation
import XCTest
@testable import SourceReadSwift

/// Covers Legado TOC metadata that previously stopped at the parser boundary:
/// volume rows (`ruleToc.isVolume`), post-processing (`ruleToc.formatJs`), and
/// metadata retention across paginated TOC pages.
final class ChapterListMetadataTests: XCTestCase {
    func testHTMLVolumeRowsBecomeVolumeNamesAndAreNotChapters() async throws {
        let tocURL = "https://fixture.example/book/html-volume/toc"
        let source = BookSource(
            bookSourceName: "HTML volume fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "div.catalog h3, div.catalog a",
                "chapterName": "h3.volume@text||a@text",
                "chapterUrl": "a@href",
                "isVolume": "h3.volume@text"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: """
                <html><body>
                  <div class="catalog">
                    <h3 class="volume">第一卷</h3>
                    <a href="/chapter/1">第一章</a>
                    <a href="/chapter/2">第二章</a>
                    <h3 class="volume">第二卷</h3>
                    <a href="/chapter/3">第三章</a>
                  </div>
                </body></html>
                """
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章", "第三章"])
        XCTAssertEqual(chapters.map(\.volumeName), ["第一卷", "第一卷", "第二卷"])
        XCTAssertEqual(chapters.map(\.index), [0, 1, 2])
    }

    func testSelectOptionTOCUsesValueAttributeForChapterURL() async throws {
        let tocURL = "https://fixture.example/book/select-option/toc"
        let source = BookSource(
            bookSourceName: "select option fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "option"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: """
                <html><body>
                  <select id="catalog">
                    <option value="/novel_1.html">第一章 陨落的天才</option>
                    <option value="/novel_2.html">第二章 斗气大陆</option>
                  </select>
                </body></html>
                """
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.title), ["第一章 陨落的天才", "第二章 斗气大陆"])
        XCTAssertEqual(chapters.map(\.url), [
            "https://fixture.example/novel_1.html",
            "https://fixture.example/novel_2.html"
        ])
    }

    func testJSONVolumeRowsSupportBooleanAndStringFlags() async throws {
        let tocURL = "https://fixture.example/book/json-volume/toc"
        let source = BookSource(
            bookSourceName: "JSON volume fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "$.chapters[*]",
                "chapterName": "$.title",
                "chapterUrl": "$.url",
                "isVolume": "$.isVolume"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: #"""
                {"chapters":[
                  {"title":"第一卷","isVolume":true},
                  {"title":"第一章","url":"/chapter/1"},
                  {"title":"第二卷","isVolume":"true"},
                  {"title":"第二章","url":"/chapter/2"}
                ]}
                """#
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(chapters.map(\.volumeName), ["第一卷", "第二卷"])
        XCTAssertEqual(chapters.map(\.index), [0, 1])
    }

    func testFormatJsRunsAfterPaginationWithOneBasedIndex() async throws {
        let tocURL = "https://fixture.example/book/format-js/toc"
        let source = BookSource(
            bookSourceName: "formatJs fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "div.catalog a",
                "chapterName": "a@text",
                "chapterUrl": "a@href",
                "formatJs": "title + '（' + index + '）'"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: """
                <html><body><div class="catalog">
                  <a href="/chapter/1">第一章</a>
                  <a href="/chapter/2">第二章</a>
                </div></body></html>
                """
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.title), ["第一章（1）", "第二章（2）"])
        XCTAssertEqual(chapters.map(\.index), [0, 1])
    }

    func testPaginationPreservesUpdateTimeAndVolumeName() async throws {
        let tocURL = "https://fixture.example/book/paged/toc"
        let page2URL = "https://fixture.example/book/paged/toc?page=2"
        let source = BookSource(
            bookSourceName: "Paged metadata fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "div.catalog a.chapter",
                "chapterName": "a@text",
                "chapterUrl": "a@href",
                "updateTime": "a@data-update",
                "volumeName": "a@data-volume",
                "nextTocUrl": "a.next@href"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: """
                <html><body>
                  <div class="catalog">
                    <a class="chapter" href="/chapter/1" data-update="2026-01-01" data-volume="第一卷">第一章</a>
                  </div>
                  <a class="next" href="\(page2URL)">下一页</a>
                </body></html>
                """,
            page2URL: """
                <html><body>
                  <div class="catalog">
                    <a class="chapter" href="/chapter/2" data-update="2026-01-02" data-volume="第二卷">第二章</a>
                  </div>
                </body></html>
                """
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(chapters.map(\.updateTime), ["2026-01-01", "2026-01-02"])
        XCTAssertEqual(chapters.map(\.volumeName), ["第一卷", "第二卷"])
        XCTAssertEqual(chapters.map(\.index), [0, 1])
        XCTAssertEqual(network.requestedURLs, [tocURL, page2URL])
    }

    func testVolumeHeaderOnlyChangesAtBoundaries() {
        let chapters = [
            BookChapter(title: "一", url: "u1", bookUrl: "b", index: 0, volumeName: "A"),
            BookChapter(title: "二", url: "u2", bookUrl: "b", index: 1, volumeName: "A"),
            BookChapter(title: "三", url: "u3", bookUrl: "b", index: 2, volumeName: "B"),
            BookChapter(title: "四", url: "u4", bookUrl: "b", index: 3, volumeName: nil)
        ]

        XCTAssertEqual(ChapterListPresenter.volumeHeader(at: 0, in: chapters), "A")
        XCTAssertNil(ChapterListPresenter.volumeHeader(at: 1, in: chapters))
        XCTAssertEqual(ChapterListPresenter.volumeHeader(at: 2, in: chapters), "B")
        XCTAssertNil(ChapterListPresenter.volumeHeader(at: 3, in: chapters))
    }

    func testPreUpdateJsRunsBeforeTocRequestAndSharesState() async throws {
        let tocURL = "https://fixture.example/book/pre-update/toc"
        let bootstrapURL = "https://fixture.example/api/toc-token"
        let source = BookSource(
            bookSourceName: "preUpdateJs fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "preUpdateJs": "var payload = JSON.parse(java.ajax('" + bootstrapURL + "')); java.put('tocPath', payload.path)",
                "chapterList": "$.@get:tocPath[*]",
                "chapterName": "$.title",
                "chapterUrl": "$.url"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            bootstrapURL: #"{"path":"chapters"}"#,
            tocURL: #"{"chapters":[{"title":"第一章","url":"/chapter/1"}]}"#
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.title), ["第一章"])
        XCTAssertEqual(network.requestedURLs, [bootstrapURL, tocURL])
    }

    func testPaginationInheritsVolumeFromPreviousPage() async throws {
        let tocURL = "https://fixture.example/book/paged-volume/toc"
        let page2URL = "https://fixture.example/book/paged-volume/toc?page=2"
        let source = BookSource(
            bookSourceName: "Paged volume fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "div.catalog h3, div.catalog a",
                "chapterName": "h3.volume@text||a@text",
                "chapterUrl": "a@href",
                "isVolume": "h3.volume@text",
                "nextTocUrl": "a.next@href"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: """
                <html><body>
                  <div class="catalog">
                    <h3 class="volume">第一卷</h3>
                    <a href="/chapter/1">第一章</a>
                    <h3 class="volume">第二卷</h3>
                  </div>
                  <a class="next" href="\(page2URL)">下一页</a>
                </body></html>
                """,
            page2URL: """
                <html><body>
                  <div class="catalog">
                    <a href="/chapter/2">第二章</a>
                  </div>
                </body></html>
                """
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(chapters.map(\.volumeName), ["第一卷", "第二卷"])
        XCTAssertEqual(chapters.map(\.index), [0, 1])
        XCTAssertEqual(network.requestedURLs, [tocURL, page2URL])
    }

    func testHTMLFallbackRulesConsumeVolumeRowsAndInheritVolume() async throws {
        let tocURL = "https://fixture.example/book/html-fallback-volume/toc"
        let source = BookSource(
            bookSourceName: "HTML fallback volume fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "div.catalog h3, div.catalog a",
                "chapterName": "span@text",
                "chapterUrl": "span@data-href",
                "isVolume": "h3.volume@text"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: """
                <html><body>
                  <div class="catalog">
                    <h3 class="volume">第一卷</h3>
                    <a href="/chapter/1">第一章</a>
                  </div>
                </body></html>
                """
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.title), ["第一章"])
        XCTAssertEqual(chapters.map(\.volumeName), ["第一卷"])
        XCTAssertEqual(chapters.map(\.index), [0])
    }

    func testReverseTocFlagReversesCollectedChapterList() async throws {
        let tocURL = "https://fixture.example/book/reversed/toc"
        let source = BookSource(
            bookSourceName: "reverseToc fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "preUpdateJs": "book.setReverseToc(true)",
                "chapterList": "div.catalog a",
                "chapterName": "a@text",
                "chapterUrl": "a@href"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: """
                <html><body><div class="catalog">
                  <a href="/chapter/3">第三章</a>
                  <a href="/chapter/2">第二章</a>
                  <a href="/chapter/1">第一章</a>
                </div></body></html>
                """
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章", "第三章"])
        XCTAssertEqual(chapters.map(\.index), [0, 1, 2])
    }

    func testReverseTocFlagStaysOffWhenSourceDoesNotRequestIt() async throws {
        let tocURL = "https://fixture.example/book/not-reversed/toc"
        let source = BookSource(
            bookSourceName: "no reverseToc fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "preUpdateJs": "book.setReverseToc(false)",
                "chapterList": "div.catalog a",
                "chapterName": "a@text",
                "chapterUrl": "a@href"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: """
                <html><body><div class="catalog">
                  <a href="/chapter/1">第一章</a>
                  <a href="/chapter/2">第二章</a>
                </div></body></html>
                """
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(chapters.map(\.index), [0, 1])
    }

    func testHTMLChapterWordCountIsParsedAndPreserved() async throws {
        let tocURL = "https://fixture.example/book/html-word-count/toc"
        let source = BookSource(
            bookSourceName: "HTML wordCount fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "div.catalog a",
                "chapterName": "a@text",
                "chapterUrl": "a@href",
                "wordCount": "a@data-words"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: """
                <html><body><div class="catalog">
                  <a href="/chapter/1" data-words="3200字">第一章</a>
                  <a href="/chapter/2" data-words=" 4100字 ">第二章</a>
                  <a href="/chapter/3">第三章</a>
                </div></body></html>
                """
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.wordCount), ["3200字", "4100字", nil])
        XCTAssertEqual(ChapterListPresenter.wordCountLabel(chapters[0]), "3200字")
        XCTAssertEqual(ChapterListPresenter.metadataLabel(chapters[0]), "3200字")
    }

    func testJSONChapterWordCountSupportsNumberStringAndFallbackKeys() async throws {
        let tocURL = "https://fixture.example/book/json-word-count/toc"
        let source = BookSource(
            bookSourceName: "JSON wordCount fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "$.chapters[*]",
                "chapterName": "$.title",
                "chapterUrl": "$.url"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: #"""
                {"chapters":[
                  {"title":"第一章","url":"/chapter/1","wordCount":3200},
                  {"title":"第二章","url":"/chapter/2","wordNum":"1.2万字"},
                  {"title":"第三章","url":"/chapter/3","words":"  800字  "}
                ]}
                """#
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.wordCount), ["3200", "1.2万字", "800字"])
    }

    func testBookChapterDecodesLegacyCacheWithoutWordCount() throws {
        let legacy = #"""
            {"title":"第一章","url":"https://fixture.example/1","bookUrl":"https://fixture.example/book","index":0,"isVip":false}
            """#
        let chapter = try JSONDecoder().decode(BookChapter.self, from: Data(legacy.utf8))
        XCTAssertNil(chapter.wordCount)
        XCTAssertNil(chapter.updateTime)
        XCTAssertNil(chapter.volumeName)
    }

    func testHTMLChapterIsPayIsParsedSeparatelyFromIsVip() async throws {
        let tocURL = "https://fixture.example/book/html-pay/toc"
        let source = BookSource(
            bookSourceName: "HTML isPay fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "div.catalog a",
                "chapterName": "a@text",
                "chapterUrl": "a@href",
                "isVip": "a@data-vip",
                "isPay": "a@data-pay"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: """
                <html><body><div class="catalog">
                  <a href="/chapter/1" data-vip="true" data-pay="false">第一章</a>
                  <a href="/chapter/2" data-vip="true" data-pay="true">第二章</a>
                  <a href="/chapter/3" data-vip="false">第三章</a>
                </div></body></html>
                """
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.isVip), [true, true, false])
        XCTAssertEqual(chapters.map(\.isPay), [false, true, nil])
    }

    func testJSONChapterIsPaySupportsBooleanStringAndMissingValue() async throws {
        let tocURL = "https://fixture.example/book/json-pay/toc"
        let source = BookSource(
            bookSourceName: "JSON isPay fixture",
            bookSourceUrl: "https://fixture.example",
            ruleToc: SourceRule(fields: [
                "chapterList": "$.chapters[*]",
                "chapterName": "$.title",
                "chapterUrl": "$.url",
                "isVip": "$.isVip",
                "isPay": "$.isPay"
            ])
        )
        let network = ChapterFixtureNetworkClient(responses: [
            tocURL: #"""
                {"chapters":[
                  {"title":"第一章","url":"/chapter/1","isVip":true,"isPay":false},
                  {"title":"第二章","url":"/chapter/2","isVip":true,"isPay":"true"},
                  {"title":"第三章","url":"/chapter/3","isVip":false}
                ]}
                """#
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: makeBook(tocURL: tocURL)))

        XCTAssertEqual(chapters.map(\.isVip), [true, true, false])
        XCTAssertEqual(chapters.map(\.isPay), [false, true, nil])
    }

    func testBookChapterDecodesLegacyCacheWithoutIsPay() throws {
        let legacy = #"""
            {"title":"第一章","url":"https://fixture.example/1","bookUrl":"https://fixture.example/book","index":0,"isVip":true}
            """#
        let chapter = try JSONDecoder().decode(BookChapter.self, from: Data(legacy.utf8))
        XCTAssertTrue(chapter.isVip)
        XCTAssertNil(chapter.isPay)

        let paid = BookChapter(
            title: "第二章",
            url: "https://fixture.example/2",
            bookUrl: "https://fixture.example/book",
            index: 1,
            isVip: true,
            isPay: true
        )
        let roundTrip = try JSONDecoder().decode(BookChapter.self, from: JSONEncoder().encode(paid))
        XCTAssertEqual(roundTrip.isPay, true)
        XCTAssertEqual(roundTrip.withIndex(5).isPay, true)
        XCTAssertEqual(roundTrip.withTitle("新标题").isPay, true)
    }

    private func makeBook(tocURL: String) -> BookDetail {
        BookDetail(
            name: "Fixture Book",
            author: "Fixture Author",
            coverUrl: nil,
            bookUrl: "https://fixture.example/book/fixture",
            tocUrl: tocURL,
            sourceName: "Fixture",
            sourceUrl: "https://fixture.example",
            intro: nil,
            latestChapter: nil
        )
    }

    private func unwrap<T>(_ result: Result<T, SourceEngineError>, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        switch result {
        case .success(let value): return value
        case .failure(let error):
            XCTFail("source pipeline failed: \(error)", file: file, line: line)
            throw error
        }
    }
}

private final class ChapterFixtureNetworkClient: SourceNetworkClient, @unchecked Sendable {
    private let responses: [String: String]
    private let lock = NSLock()
    private var recordedURLs: [String] = []

    init(responses: [String: String]) {
        self.responses = responses
    }

    var requestedURLs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedURLs
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        lock.lock()
        recordedURLs.append(request.url.absoluteString)
        lock.unlock()
        guard let body = responses[request.url.absoluteString] else {
            return .failure(.network("fixture response missing for \(request.url.absoluteString)"))
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let contentType = trimmed.first == "{" || trimmed.first == "[" ? "application/json" : "text/html"
        return .success(SourceResponse(
            url: request.url,
            statusCode: 200,
            headers: ["Content-Type": contentType],
            body: body,
            data: Data(body.utf8)
        ))
    }
}