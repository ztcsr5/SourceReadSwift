import XCTest
@testable import SourceReadSwift
import UIKit

final class CustomFontAndExportTests: XCTestCase {
    @MainActor
    func testCustomFontManagerInitializationAndFallback() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let manager = CustomFontManager(fileManager: .default)

        XCTAssertNotNil(manager.fontsDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.fontsDirectory.path))

        // Non-existent font returns nil
        let nonExistent = manager.uiFont(postScriptName: "NonExistentFontFamily12345", size: 16)
        XCTAssertNil(nonExistent)
    }

    func testReaderFontFamilyResolvesKaitiAndRounded() {
        let kaitiFont = ReaderFontFamily.kaiti.uiFont(ofSize: 18)
        XCTAssertNotNil(kaitiFont)
        XCTAssertEqual(kaitiFont.pointSize, 18)

        let roundedFont = ReaderFontFamily.rounded.uiFont(ofSize: 20)
        XCTAssertNotNil(roundedFont)
        XCTAssertEqual(roundedFont.pointSize, 20)

        let customFont = ReaderFontFamily.custom.uiFont(ofSize: 16, customPostScriptName: "NonExistent")
        XCTAssertNotNil(customFont) // Falls back to system font gracefully
        XCTAssertEqual(customFont.pointSize, 16)
    }

    func testBookExportServiceGeneratesCleanPlainTextFile() throws {
        let exporter = BookExportService()
        let book = BookshelfBook(
            id: "test-book-export",
            title: "凡人修仙传",
            author: "忘语",
            coverURL: nil,
            sourceName: "起点中文",
            sourceURL: "https://example.com/source",
            bookURL: "https://example.com/book/1",
            intro: "一个普通的山村穷小子，偶然之下跨入仙途。",
            totalChapters: 2,
            currentChapterIndex: 1,
            lastReadAt: Date()
        )

        let chapter1 = ChapterContent(
            chapter: BookChapter(title: "第一章 山边小村", url: "https://example.com/1", bookUrl: book.bookURL, index: 0, isVip: false),
            title: "第一章 山边小村",
            paragraphs: ["二愣子睁开眼，天刚蒙蒙亮。", "村口的鸡叫了三遍。"],
            nextContentUrl: nil
        )

        let chapter2 = ChapterContent(
            chapter: BookChapter(title: "第二章 离家", url: "https://example.com/2", bookUrl: book.bookURL, index: 1, isVip: false),
            title: "第二章 离家",
            paragraphs: ["三叔骑着毛驴来了。", "包裹很轻，心思很重。"],
            nextContentUrl: nil
        )

        let fileURL = try exporter.exportBookToPlainText(book: book, cachedChapters: [chapter1, chapter2])

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(fileURL.pathExtension, "txt")
        XCTAssertTrue(fileURL.lastPathComponent.contains("凡人修仙传"))

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("《凡人修仙传》"))
        XCTAssertTrue(content.contains("作者：忘语"))
        XCTAssertTrue(content.contains("【内容简介】"))
        XCTAssertTrue(content.contains("一个普通的山村穷小子"))
        XCTAssertTrue(content.contains("第 1 章 第一章 山边小村"))
        XCTAssertTrue(content.contains("二愣子睁开眼，天刚蒙蒙亮。"))
        XCTAssertTrue(content.contains("第 2 章 第二章 离家"))
        XCTAssertTrue(content.contains("三叔骑着毛驴来了。"))

        // Clean up
        try? FileManager.default.removeItem(at: fileURL)
    }
}
