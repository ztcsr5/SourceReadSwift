import Foundation
import XCTest
@testable import SourceReadSwift

/// Locks the Legado metadata chain that used to be dropped on the floor:
/// `ruleSearch.wordCount`, `ruleSearch.checkKeyWord`, `ruleToc.updateTime`,
/// `ruleToc.isVip` and `ruleToc.volumeName`.
final class SourceMetadataChainTests: XCTestCase {

    // MARK: - Search: HTML

    func testHTMLSearchExtractsWordCountAndFiltersByCheckKeyWord() throws {
        let source = BookSource(
            bookSourceName: "Metadata HTML",
            bookSourceUrl: "https://example.com",
            ruleSearch: SourceRule(fields: [
                "bookList": ".book",
                "name": ".title@text",
                "bookUrl": "a@href",
                "author": ".author@text",
                "wordCount": ".words@text",
                "checkKeyWord": ".title@text"
            ])
        )
        let response = SourceResponse(
            url: URL(string: "https://example.com/search?q=%E5%89%91%E6%9D%A5")!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <div class="book">
                <a class="title" href="/book/1">剑来</a>
                <span class="author">烽火戏诸侯</span>
                <span class="words">120万字</span>
              </div>
              <div class="book">
                <a class="title" href="/book/2">无关之书</a>
                <span class="author">某人</span>
                <span class="words">30万字</span>
              </div>
            </body></html>
            """,
            data: Data()
        )

        let result = SearchResultParser().parse(source: source, response: response, keyword: "剑来")
        guard case .success(let books) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.name, "剑来")
        XCTAssertEqual(books.first?.wordCount, "120万字")
        XCTAssertEqual(books.first?.checkKeyWord, "剑来")
    }

    func testHTMLSearchWithoutKeywordKeepsAllRowsButStillCapturesMetadata() throws {
        let source = BookSource(
            bookSourceName: "Metadata HTML No Keyword",
            bookSourceUrl: "https://example.com",
            ruleSearch: SourceRule(fields: [
                "bookList": ".book",
                "name": ".title@text",
                "bookUrl": "a@href",
                "wordCount": ".words@text",
                "checkKeyWord": ".title@text"
            ])
        )
        let response = SourceResponse(
            url: URL(string: "https://example.com/search")!,
            statusCode: 200,
            headers: [:],
            body: #"<html><body><div class="book"><a class="title" href="/book/1">A</a><span class="words">10万字</span></div><div class="book"><a class="title" href="/book/2">B</a><span class="words">20万字</span></div></body></html>"#,
            data: Data()
        )

        let result = SearchResultParser().parse(source: source, response: response)
        guard case .success(let books) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(books.count, 2)
        XCTAssertEqual(books.map(\.wordCount), ["10万字", "20万字"])
    }

    // MARK: - Search: JSON

    func testJSONSearchExtractsWordCountAndFiltersByCheckKeyWord() throws {
        let source = BookSource(
            bookSourceName: "Metadata JSON",
            bookSourceUrl: "https://api.example.com",
            ruleSearch: SourceRule(fields: [
                "bookList": "$.data[*]",
                "name": "$.name",
                "bookUrl": "$.url",
                "author": "$.author",
                "wordCount": "$.words",
                "checkKeyWord": "$.name"
            ])
        )
        let response = SourceResponse(
            url: URL(string: "https://api.example.com/search?q=abc")!,
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: """
            {"data":[
              {"name":"剑来","author":"烽火戏诸侯","url":"/book/1","words":"120万字"},
              {"name":"别的书","author":"某人","url":"/book/2","words":"30万字"}
            ]}
            """,
            data: Data()
        )

        let result = SearchResultParser().parse(source: source, response: response, keyword: "剑来")
        guard case .success(let books) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.wordCount, "120万字")
        XCTAssertEqual(books.first?.checkKeyWord, "剑来")
    }

    // MARK: - TOC: HTML

    func testHTMLChapterListExtractsUpdateTimeVipAndVolume() throws {
        let source = BookSource(
            bookSourceName: "TOC HTML",
            bookSourceUrl: "https://example.com",
            ruleToc: SourceRule(fields: [
                "chapterList": ".chapter-list li",
                "chapterName": "a@text",
                "chapterUrl": "a@href",
                "updateTime": ".time@text",
                "isVip": ".vip@text",
                "volumeName": ".volume@text"
            ])
        )
        let book = makeBook()
        let response = SourceResponse(
            url: URL(string: "https://example.com/book/1")!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body><ul class="chapter-list">
              <li><span class="volume">第一卷</span><a href="/c/1">第一章 开始</a><span class="time">2026-10-01</span><span class="vip">true</span></li>
              <li><span class="volume">第一卷</span><a href="/c/2">第二章 继续</a><span class="time">2026-10-02</span><span class="vip">false</span></li>
            </ul></body></html>
            """,
            data: Data()
        )

        let result = ChapterListParser().parsePage(source: source, book: book, response: response)
        guard case .success(let page) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(page.chapters.count, 2)
        XCTAssertEqual(page.chapters[0].updateTime, "2026-10-01")
        XCTAssertEqual(page.chapters[0].volumeName, "第一卷")
        XCTAssertTrue(page.chapters[0].isVip)
        XCTAssertFalse(page.chapters[1].isVip)
    }

    // MARK: - TOC: JSON

    func testJSONChapterListExtractsUpdateTimeVipAndVolume() throws {
        let source = BookSource(
            bookSourceName: "TOC JSON",
            bookSourceUrl: "https://api.example.com",
            ruleToc: SourceRule(fields: [
                "chapterList": "$.chapters[*]",
                "chapterName": "$.title",
                "chapterUrl": "$.url",
                "updateTime": "$.time",
                "isVip": "$.vip",
                "volumeName": "$.volume"
            ])
        )
        let book = makeBook()
        let response = SourceResponse(
            url: URL(string: "https://api.example.com/book/1")!,
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: """
            {"chapters":[
              {"title":"第一章 开始","url":"/c/1","time":"2026-10-01","vip":"1","volume":"第一卷"},
              {"title":"第二章 继续","url":"/c/2","time":"2026-10-02","vip":"0","volume":"第一卷"}
            ]}
            """,
            data: Data()
        )

        let result = ChapterListParser().parsePage(source: source, book: book, response: response)
        guard case .success(let page) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(page.chapters.count, 2)
        XCTAssertEqual(page.chapters[0].updateTime, "2026-10-01")
        XCTAssertEqual(page.chapters[0].volumeName, "第一卷")
        XCTAssertTrue(page.chapters[0].isVip)
        XCTAssertFalse(page.chapters[1].isVip)
    }

    // MARK: - Book detail: HTML

    func testHTMLBookDetailExtractsWordCountStatusUpdateTimeAndKind() throws {
        let source = BookSource(
            bookSourceName: "Detail HTML",
            bookSourceUrl: "https://example.com",
            ruleBookInfo: SourceRule(fields: [
                "name": ".title@text",
                "author": ".author@text",
                "wordCount": ".words@text",
                "status": ".status@text",
                "updateTime": ".updated@text",
                "kind": ".kind@text",
                "intro": ".intro@text",
                "latestChapter": ".latest@text"
            ])
        )
        let book = makeSearchBook()
        let response = SourceResponse(
            url: URL(string: "https://example.com/book/1")!,
            statusCode: 200,
            headers: ["Content-Type": "text/html"],
            body: """
            <html><body>
              <h1 class="title">剑来</h1>
              <span class="author">烽火戏诸侯</span>
              <span class="words">120万字</span>
              <span class="status">连载中</span>
              <span class="updated">2026-10-20</span>
              <span class="kind">仙侠</span>
              <p class="intro">简介</p>
              <span class="latest">第一千章</span>
            </body></html>
            """,
            data: Data()
        )

        let result = BookDetailParser().parse(source: source, book: book, response: response)
        guard case .success(let detail) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(detail.name, "剑来")
        XCTAssertEqual(detail.wordCount, "120万字")
        XCTAssertEqual(detail.status, "连载中")
        XCTAssertEqual(detail.updateTime, "2026-10-20")
        XCTAssertEqual(detail.kind, "仙侠")
        XCTAssertEqual(detail.latestChapter, "第一千章")
    }

    // MARK: - Book detail: JSON

    func testJSONBookDetailExtractsWordCountStatusUpdateTimeAndKind() throws {
        let source = BookSource(
            bookSourceName: "Detail JSON",
            bookSourceUrl: "https://api.example.com",
            ruleBookInfo: SourceRule(fields: [
                "name": "$.data.name",
                "author": "$.data.author",
                "wordCount": "$.data.words",
                "status": "$.data.status",
                "updateTime": "$.data.updated",
                "kind": "$.data.kind",
                "intro": "$.data.intro",
                "latestChapter": "$.data.latest"
            ])
        )
        let book = makeSearchBook()
        let response = SourceResponse(
            url: URL(string: "https://api.example.com/book/1")!,
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: """
            {"data":{
              "name":"剑来",
              "author":"烽火戏诸侯",
              "words":"120万字",
              "status":"连载中",
              "updated":"2026-10-20",
              "kind":"仙侠",
              "intro":"简介",
              "latest":"第一千章"
            }}
            """,
            data: Data()
        )

        let result = BookDetailParser().parse(source: source, book: book, response: response)
        guard case .success(let detail) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(detail.name, "剑来")
        XCTAssertEqual(detail.wordCount, "120万字")
        XCTAssertEqual(detail.status, "连载中")
        XCTAssertEqual(detail.updateTime, "2026-10-20")
        XCTAssertEqual(detail.kind, "仙侠")
        XCTAssertEqual(detail.latestChapter, "第一千章")
    }

    // MARK: - Chapter list presentation

    func testChapterListPresenterEmitsVolumeHeaderOnlyOnChange() {
        let chapters = [
            BookChapter(title: "一", url: "/1", bookUrl: "/b", index: 0, updateTime: " 2026-10-01 ", volumeName: "第一卷"),
            BookChapter(title: "二", url: "/2", bookUrl: "/b", index: 1, updateTime: "", volumeName: "第一卷"),
            BookChapter(title: "三", url: "/3", bookUrl: "/b", index: 2, updateTime: nil, volumeName: "第二卷")
        ]

        XCTAssertEqual(ChapterListPresenter.volumeHeader(at: 0, in: chapters), "第一卷")
        XCTAssertNil(ChapterListPresenter.volumeHeader(at: 1, in: chapters))
        XCTAssertEqual(ChapterListPresenter.volumeHeader(at: 2, in: chapters), "第二卷")
        XCTAssertNil(ChapterListPresenter.volumeHeader(at: 9, in: chapters))
    }

    func testChapterListPresenterUpdateLabelTrimsAndDropsEmpty() {
        let trimmed = BookChapter(title: "一", url: "/1", bookUrl: "/b", index: 0, updateTime: " 2026-10-01 ", volumeName: nil)
        let empty = BookChapter(title: "二", url: "/2", bookUrl: "/b", index: 1, updateTime: "   ", volumeName: nil)
        let missing = BookChapter(title: "三", url: "/3", bookUrl: "/b", index: 2, updateTime: nil, volumeName: nil)

        XCTAssertEqual(ChapterListPresenter.updateLabel(trimmed), "2026-10-01")
        XCTAssertNil(ChapterListPresenter.updateLabel(empty))
        XCTAssertNil(ChapterListPresenter.updateLabel(missing))
    }

    func testChapterListPresenterBuildsMetadataLabelFromUpdateAndWordCount() {
        let both = BookChapter(
            title: "一", url: "/1", bookUrl: "/b", index: 0,
            updateTime: " 2026-10-01 ", volumeName: nil, wordCount: " 3200字 "
        )
        let wordOnly = BookChapter(
            title: "二", url: "/2", bookUrl: "/b", index: 1,
            updateTime: "", volumeName: nil, wordCount: "1.2万字"
        )
        let updateOnly = BookChapter(
            title: "三", url: "/3", bookUrl: "/b", index: 2,
            updateTime: "2026-10-02", volumeName: nil, wordCount: "   "
        )
        let neither = BookChapter(
            title: "四", url: "/4", bookUrl: "/b", index: 3,
            updateTime: nil, volumeName: nil, wordCount: nil
        )

        XCTAssertEqual(ChapterListPresenter.metadataLabel(both), "更新 2026-10-01 · 3200字")
        XCTAssertEqual(ChapterListPresenter.metadataLabel(wordOnly), "1.2万字")
        XCTAssertEqual(ChapterListPresenter.metadataLabel(updateOnly), "更新 2026-10-02")
        XCTAssertNil(ChapterListPresenter.metadataLabel(neither))
    }

    func testChapterListPresenterSkipsBlankVolumeNames() {
        let chapters = [
            BookChapter(title: "一", url: "/1", bookUrl: "/b", index: 0, volumeName: "  "),
            BookChapter(title: "二", url: "/2", bookUrl: "/b", index: 1, volumeName: nil)
        ]

        XCTAssertNil(ChapterListPresenter.volumeHeader(at: 0, in: chapters))
        XCTAssertNil(ChapterListPresenter.volumeHeader(at: 1, in: chapters))
    }
    // MARK: - Backward compatibility

    func testSearchBookDecodesLegacyPayloadWithoutMetadataFields() throws {
        let legacy = """
        {"name":"旧书","author":"作者","coverUrl":null,"bookUrl":"https://example.com/b/1","sourceName":"S","sourceUrl":"https://example.com","intro":null,"kind":null,"lastChapter":null}
        """
        let book = try JSONDecoder().decode(SearchBook.self, from: Data(legacy.utf8))
        XCTAssertNil(book.wordCount)
        XCTAssertNil(book.checkKeyWord)
    }

    func testBookDetailDecodesLegacyPayloadWithoutDetailMetadata() throws {
        let legacy = """
        {"name":"旧书","author":"作者","coverUrl":null,"bookUrl":"https://example.com/b/1","tocUrl":null,"sourceName":"S","sourceUrl":"https://example.com","intro":null,"latestChapter":null}
        """
        let detail = try JSONDecoder().decode(BookDetail.self, from: Data(legacy.utf8))
        XCTAssertNil(detail.wordCount)
        XCTAssertNil(detail.status)
        XCTAssertNil(detail.updateTime)
        XCTAssertNil(detail.kind)
    }

    func testBookChapterDecodesLegacyPayloadWithoutMetadataFields() throws {
        let legacy = """
        {"title":"第一章","url":"https://example.com/c/1","bookUrl":"https://example.com/b/1","index":0,"isVip":false}
        """
        let chapter = try JSONDecoder().decode(BookChapter.self, from: Data(legacy.utf8))
        XCTAssertNil(chapter.updateTime)
        XCTAssertNil(chapter.volumeName)
    }

    private func makeSearchBook() -> SearchBook {
        SearchBook(
            name: "剑来",
            author: "烽火戏诸侯",
            coverUrl: nil,
            bookUrl: "https://example.com/book/1",
            sourceName: "Detail",
            sourceUrl: "https://example.com"
        )
    }

    private func makeBook() -> BookDetail {
        BookDetail(
            name: "测试书",
            author: "作者",
            coverUrl: nil,
            bookUrl: "https://example.com/book/1",
            tocUrl: "https://example.com/book/1",
            sourceName: "TOC",
            sourceUrl: "https://example.com",
            intro: nil,
            latestChapter: nil
        )
    }
}