import XCTest
import ZIPFoundation
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

    func testArchiveContainsTextCoverAndMetadata() throws {
        let result = try BookExportService().exportBookArchive(
            book: fixtureBook(),
            cachedChapters: [chapter(2), chapter(1)],
            coverJPEG: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            totalChapterCount: 5
        )
        defer { try? FileManager.default.removeItem(at: result.url) }
        XCTAssertEqual(result.url.pathExtension, "zip")
        XCTAssertEqual(result.exportedChapterCount, 2)
        XCTAssertEqual(result.totalChapterCount, 5)
        XCTAssertTrue(result.isPartial)

        let archive = try XCTUnwrap(Archive(url: result.url, accessMode: .read))
        var entries: [String: Entry] = [:]
        for entry in archive { entries[entry.path] = entry }
        XCTAssertEqual(Set(entries.keys), ["正文.txt", "cover.jpg", "metadata.json"])

        let textData = try extract("正文.txt", from: archive, entries: entries)
        let text = String(decoding: textData, as: UTF8.self)
        XCTAssertTrue(text.contains("第 2 章 章节1"))
        XCTAssertTrue(text.contains("第 3 章 章节2"))
        XCTAssertLessThan(try XCTUnwrap(text.range(of: "第 2 章 章节1")).lowerBound,
                          try XCTUnwrap(text.range(of: "第 3 章 章节2")).lowerBound)

        let metadataData = try extract("metadata.json", from: archive, entries: entries)
        let metadata = try JSONDecoder().decode(ArchiveMetadata.self, from: metadataData)
        XCTAssertEqual(metadata.title, "导出回归")
        XCTAssertEqual(metadata.exportedChapterCount, 2)
        XCTAssertEqual(metadata.totalChapterCount, 5)
        XCTAssertEqual(metadata.chapters.map(\.index), [1, 2])

        let coverData = try extract("cover.jpg", from: archive, entries: entries)
        XCTAssertEqual(coverData, Data([0xFF, 0xD8, 0xFF, 0xD9]))
    }

    func testArchiveWithoutCoverOmitsTheCoverEntry() throws {
        let result = try BookExportService().exportBookArchive(
            book: fixtureBook(), cachedChapters: [chapter(1)], coverJPEG: nil)
        defer { try? FileManager.default.removeItem(at: result.url) }
        let archive = try XCTUnwrap(Archive(url: result.url, accessMode: .read))
        XCTAssertEqual(Set(archive.map(\.path)), ["正文.txt", "metadata.json"])
    }

    func testArchiveRejectsAnEmptyChapterCache() {
        XCTAssertThrowsError(try BookExportService().exportBookArchive(
            book: fixtureBook(), cachedChapters: [], coverJPEG: nil)) { error in
            XCTAssertEqual(error as? BookExportError, .noContent)
        }
    }

    private struct ArchiveMetadata: Decodable {
        struct Chapter: Decodable {
            let index: Int
            let title: String
        }
        let title: String
        let author: String
        let sourceName: String
        let sourceURL: String
        let bookURL: String
        let exportedChapterCount: Int
        let totalChapterCount: Int
        let chapters: [Chapter]
    }

    private func extract(_ path: String, from archive: Archive, entries: [String: Entry]) throws -> Data {
        let entry = try XCTUnwrap(entries[path])
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        return data
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
