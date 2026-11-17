import XCTest
@testable import SourceReadSwift

final class BookReplaceRuleCompatibilityTests: XCTestCase {
    func testDetailRulePersistsReplacementOverrideForBothResponseFormats() throws {
        let book = SearchBook(name: "Story", author: nil, coverUrl: nil,
            bookUrl: "https://replace.invalid/book", sourceName: "Fixture",
            sourceUrl: "https://replace.invalid")
        for (body, contentType) in [("<h1>Story</h1>", "text/html"), (#"{"title":"Story"}"#, "application/json")] {
            let source = BookSource(bookSourceName: "Fixture", bookSourceUrl: book.sourceUrl,
                ruleBookInfo: .init(fields: ["name": "@js:book.setUseReplaceRule(false);book.name"]))
            let response = SourceResponse(url: URL(string: book.bookUrl)!, statusCode: 200,
                headers: ["Content-Type": contentType], body: body, data: Data(body.utf8))
            let detail = try BookDetailParser().parse(source: source, book: book, response: response).get()
            XCTAssertEqual(detail.useReplaceRule, false)
        }
    }

    func testContentOverrideSkipsOnlyGlobalRulesAndDoesNotLeakToAnotherBook() throws {
        let context = RuleExecutionContext()
        let parser = ContentParser(executionContext: context)
        let source = BookSource(bookSourceName: "Fixture", bookSourceUrl: "https://replace.invalid",
            ruleContent: .init(fields: ["content": "$.prose", "replaceRegex": "源内##已解码"]))
        let body = #"{"prose":"源内正文，全局词应保留。"}"#
        let first = makeChapter(book: "first", useReplaceRule: false)
        let second = makeChapter(book: "second", useReplaceRule: nil)
        let response = SourceResponse(url: URL(string: first.url)!, statusCode: 200,
            headers: ["Content-Type": "application/json"], body: body, data: Data(body.utf8))
        let rules = ["全局词##全局已净化"]

        let disabled = try parser.parse(source: source, chapter: first, response: response, globalPurifyRules: rules).get()
        let enabled = try parser.parse(source: source, chapter: second, response: response, globalPurifyRules: rules).get()
        XCTAssertEqual(disabled.paragraphs, ["已解码正文，全局词应保留。"])
        XCTAssertEqual(disabled.chapter.useReplaceRule, false)
        XCTAssertEqual(enabled.paragraphs, ["已解码正文，全局已净化应保留。"])
        XCTAssertNil(enabled.chapter.useReplaceRule)
    }

    func testContentRuleCanDisableGlobalReplacementBeforeTransformingHTML() throws {
        let source = BookSource(bookSourceName: "Fixture", bookSourceUrl: "https://replace.invalid",
            ruleContent: .init(fields: [
                "content": "#content@text@js:book.setUseReplaceRule(false);result",
                "replaceRegex": "源内##已解码"
            ]))
        let chapter = makeChapter(book: "html", useReplaceRule: nil)
        let body = "<div id='content'>源内正文，全局词应保留。</div>"
        let response = SourceResponse(url: URL(string: chapter.url)!, statusCode: 200,
            headers: ["Content-Type": "text/html"], body: body, data: Data(body.utf8))
        let content = try ContentParser().parse(source: source, chapter: chapter, response: response,
            globalPurifyRules: ["全局词##全局已净化"]).get()
        XCTAssertEqual(content.paragraphs, ["已解码正文，全局词应保留。"])
        XCTAssertEqual(content.chapter.useReplaceRule, false)
    }

    func testChapterCopiesKeepReplacementOverrideAndDefaultImagePolicy() throws {
        let original = makeChapter(book: "copies", useReplaceRule: false)
        XCTAssertEqual(original.withIndex(9).useReplaceRule, false)
        XCTAssertEqual(original.withTitle("Renamed").useReplaceRule, false)
        XCTAssertFalse(original.usesGlobalPurifyRules)
        XCTAssertFalse(original.withUseReplaceRule(nil, mediaKind: .comic).usesGlobalPurifyRules)
        XCTAssertTrue(original.withUseReplaceRule(true, mediaKind: .comic).usesGlobalPurifyRules)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        legacy.removeValue(forKey: "useReplaceRule")
        let decoded = try JSONDecoder().decode(BookChapter.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.useReplaceRule)
        XCTAssertTrue(decoded.usesGlobalPurifyRules)
    }

    private func makeChapter(book: String, useReplaceRule: Bool?) -> BookChapter {
        BookChapter(title: "第一章", url: "https://replace.invalid/\(book)/1",
            bookUrl: "https://replace.invalid/\(book)", index: 0, useReplaceRule: useReplaceRule)
    }
}
