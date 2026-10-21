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

    // MARK: - Backward compatibility

    func testSearchBookDecodesLegacyPayloadWithoutMetadataFields() throws {
        let legacy = """
        {"name":"旧书","author":"作者","coverUrl":null,"bookUrl":"https://example.com/b/1","sourceName":"S","sourceUrl":"https://example.com","intro":null,"kind":null,"lastChapter":null}
        """
        let book = try JSONDecoder().decode(SearchBook.self, from: Data(legacy.utf8))
        XCTAssertNil(book.wordCount)
        XCTAssertNil(book.checkKeyWord)
    }

    func testBookChapterDecodesLegacyPayloadWithoutMetadataFields() throws {
        let legacy = """
        {"title":"第一章","url":"https://example.com/c/1","bookUrl":"https://example.com/b/1","index":0,"isVip":false}
        """
        let chapter = try JSONDecoder().decode(BookChapter.self, from: Data(legacy.utf8))
        XCTAssertNil(chapter.updateTime)
        XCTAssertNil(chapter.volumeName)
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