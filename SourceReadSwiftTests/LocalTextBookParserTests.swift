import XCTest
@testable import SourceReadSwift

final class LocalTextBookParserTests: XCTestCase {
    func testParsesPlainTextIntoParagraphs() {
        let text = "第一段\n\n第二段\r\n第三段"
        let book = LocalTextBookParser().parse(data: Data(text.utf8), fileName: "MyBook.txt")

        XCTAssertEqual(book.title, "MyBook")
        XCTAssertEqual(book.author, "Local")
        XCTAssertEqual(book.paragraphs, ["第一段", "第二段", "第三段"])
        XCTAssertEqual(book.chapters.count, 1)
        XCTAssertEqual(book.chapters.first?.title, "全文")
    }

    func testSplitsTextIntoChapters() {
        let text = """
        第一章 开始
        第一段
        第二段
        第二章 继续
        第三段
        """
        let book = LocalTextBookParser().parse(data: Data(text.utf8), fileName: "MyBook.txt")

        XCTAssertEqual(book.chapters.count, 2)
        XCTAssertEqual(book.chapters[0].title, "第一章 开始")
        XCTAssertEqual(book.chapters[0].paragraphs, ["第一段", "第二段"])
        XCTAssertEqual(book.chapters[1].title, "第二章 继续")
        XCTAssertEqual(book.chapters[1].paragraphs, ["第三段"])
    }

    func testParsesMarkdownHeadingsIntoChapters() {
        let text = """
        # 第一章 启程
        春风吹过山谷。
        ## 第二章 征途
        踏上未知的远方。
        """
        let book = LocalTextBookParser().parse(data: Data(text.utf8), fileName: "Novel.txt")

        XCTAssertEqual(book.chapters.count, 2)
        XCTAssertEqual(book.chapters[0].title, "第一章 启程")
        XCTAssertEqual(book.chapters[0].paragraphs, ["春风吹过山谷。"])
        XCTAssertEqual(book.chapters[1].title, "第二章 征途")
        XCTAssertEqual(book.chapters[1].paragraphs, ["踏上未知的远方。"])
    }
}
