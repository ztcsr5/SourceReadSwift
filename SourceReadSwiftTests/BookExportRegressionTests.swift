import XCTest
@testable import SourceReadSwift

final class BookExportRegressionTests: XCTestCase {
    func testRepeatedExportsDoNotOverwriteFilesAlreadyShared() throws {
        let book = fixtureBook()
        let first = try BookExportService().exportBookToPlainText(book: book, cachedChapters: [chapter(1)])
        defer { try? FileManager.default.removeItem(at: first) }
        let original = try Data(contentsOf: first)
        let second = try BookExportService().exportBookToPlainText(book: book, cachedChapters: [chapter(2)])
        defer { try? FileManager.default.removeItem(at: second) }
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), original)
    }

    func testChapterOrderAndNumbersFollowTheBookDirectory() throws {
        let file = try BookExportService().exportBookToPlainText(book: fixtureBook(), cachedChapters: [chapter(9), chapter(2)])
        defer { try? FileManager.default.removeItem(at: file) }
        let text = try String(contentsOf: file, encoding: .utf8)
        let earlier = try XCTUnwrap(text.range(of: "第 3 章 章节2"))
        let later = try XCTUnwrap(text.range(of: "第 10 章 章节9"))
        XCTAssertLessThan(earlier.lowerBound, later.lowerBound)
        XCTAssertTrue(text.contains("导出时间："), "Export time exists even when the book has never been read")
    }

    func testLongTitlesAndControlCharactersProduceAUsableFileName() throws {
        let file = try BookExportService().exportBookToPlainText(
            book: fixtureBook(title: String(repeating: "长标题", count: 100) + "\n\u{0000}/"), cachedChapters: [])
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertLessThanOrEqual(file.lastPathComponent.utf8.count, 255)
        XCTAssertFalse(file.lastPathComponent.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    private func fixtureBook(title: String = "导出回归") -> BookshelfBook {
        BookshelfBook(id: UUID().uuidString, title: title, author: "演示", coverURL: nil,
            sourceName: "离线", sourceURL: "fixture", bookURL: "fixture/book", intro: nil)
    }

    private func chapter(_ index: Int) -> ChapterContent {
        ChapterContent(chapter: BookChapter(title: "章节\(index)", url: "fixture/\(index)", bookUrl: "fixture/book", index: index),
            title: "章节\(index)", paragraphs: ["正文\(index)"])
    }
}
