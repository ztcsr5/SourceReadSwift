import XCTest
import ZIPFoundation
@testable import SourceReadSwift

final class BookExportRegressionTests: XCTestCase {
    func testExportedEPUBReimportsWithTheSameMetadataAndOrderedProse() throws {
        let first = ChapterContent(chapter: chapter(2).chapter, title: "第二章 & 湖边",
            paragraphs: ["第一行 <正文>。", "第二行 👩🏽‍💻，保留 Unicode。"])
        let later = ChapterContent(chapter: chapter(9).chapter, title: "第九章 · 远山",
            paragraphs: ["后面的章节不会跑到前面。"])
        let book = fixtureBook(title: "书名 & <山水>")
        let exported = try BookExportService().exportBook(book: book, cachedChapters: [later, first],
            format: .epub, coverJPEG: nil, totalChapterCount: 2)
        defer { try? FileManager.default.removeItem(at: exported.url) }
        let imported = try LocalEPUBBookParser().parse(fileURL: exported.url)
        XCTAssertEqual(imported.title, book.title)
        XCTAssertEqual(imported.author, book.author)
        XCTAssertEqual(imported.chapters.map(\.title), [first.title, later.title])
        XCTAssertTrue(imported.chapters[0].paragraphs.contains(first.paragraphs[0]))
        XCTAssertTrue(imported.chapters[0].paragraphs.contains(first.paragraphs[1]))
        XCTAssertTrue(imported.chapters[1].paragraphs.contains(later.paragraphs[0]))
    }

    @MainActor func testExportKeepsAllFetchedChaptersBeyondTheReaderLRU() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ChapterContentCacheStore(persistence: ChapterContentCachePersistence(rootURL: root), maxEntryCount: 2)
        let chapters = (0..<12).map { chapter($0).chapter }
        let source = BookSource(bookSourceName: "Export", bookSourceUrl: "https://export.invalid")
        let engine = ExportFixtureEngine()
        var progress: [Int] = []
        let exported = await BookExportChapterLoader.load(chapters: chapters, cachedChapters: [],
            source: source, engine: engine, cacheStore: cache, purifyRules: []) { count, _ in progress.append(count) }
        XCTAssertEqual(exported.map(\.chapter.index), Array(0..<12))
        XCTAssertEqual(progress.last, 12)
        XCTAssertEqual(cache.entries.count, 2, "Export accumulation must not turn disposable prefetch into a whole-book archive")
        let requests = await engine.requestCount
        XCTAssertEqual(requests, 12)
        let file = try BookExportService().exportBook(book: fixtureBook(), cachedChapters: exported,
            format: .txt, coverJPEG: nil, totalChapterCount: 12)
        defer { try? FileManager.default.removeItem(at: file.url) }
        let text = try String(contentsOf: file.url, encoding: .utf8)
        XCTAssertTrue(text.contains("EXPORT-0"))
        XCTAssertTrue(text.contains("EXPORT-11"))
    }

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

    func testUnifiedExportSupportsTXTEPUBAndZIP() throws {
        let book = fixtureBook()
        let chapters = [chapter(2), chapter(1)]

        let txt = try BookExportService().exportBook(
            book: book, cachedChapters: chapters, format: .txt, coverJPEG: nil)
        defer { try? FileManager.default.removeItem(at: txt.url) }
        XCTAssertEqual(txt.format, .txt)
        XCTAssertEqual(txt.url.pathExtension, "txt")
        XCTAssertEqual(txt.exportedChapterCount, 2)
        XCTAssertTrue(try String(contentsOf: txt.url, encoding: .utf8).contains("第 2 章 章节1"))

        let epub = try BookExportService().exportBook(
            book: book, cachedChapters: chapters, format: .epub,
            coverJPEG: Data([0xFF, 0xD8, 0xFF, 0xD9]), totalChapterCount: 4)
        defer { try? FileManager.default.removeItem(at: epub.url) }
        XCTAssertEqual(epub.format, .epub)
        XCTAssertEqual(epub.url.pathExtension, "epub")
        XCTAssertTrue(epub.isPartial)
        let archive = try XCTUnwrap(Archive(url: epub.url, accessMode: .read))
        let entries = Dictionary(uniqueKeysWithValues: archive.map { ($0.path, $0) })
        XCTAssertEqual(Array(archive).first?.path, "mimetype")
        XCTAssertEqual(Set(entries.keys), Set([
            "mimetype", "META-INF/container.xml", "OEBPS/content.opf",
            "OEBPS/nav.xhtml", "OEBPS/toc.ncx", "OEBPS/style.css",
            "OEBPS/cover.jpg", "OEBPS/cover.xhtml",
            "OEBPS/chapter-0001.xhtml", "OEBPS/chapter-0002.xhtml"
        ]))
        let mimetype = try extract("mimetype", from: archive, entries: entries)
        XCTAssertEqual(String(decoding: mimetype, as: UTF8.self), "application/epub+zip")
        let firstChapter = try extract("OEBPS/chapter-0001.xhtml", from: archive, entries: entries)
        XCTAssertTrue(String(decoding: firstChapter, as: UTF8.self).contains("章节1"))
        let package = try extract("OEBPS/content.opf", from: archive, entries: entries)
        XCTAssertTrue(String(decoding: package, as: UTF8.self).contains("<dc:title>导出回归</dc:title>"))

        let zip = try BookExportService().exportBook(
            book: book, cachedChapters: chapters, format: .zip, coverJPEG: nil)
        defer { try? FileManager.default.removeItem(at: zip.url) }
        XCTAssertEqual(zip.format, .zip)
        XCTAssertEqual(zip.url.pathExtension, "zip")
    }

    func testEPUBEscapesChapterXMLAndOrdersChaptersByDirectoryIndex() throws {
        let book = fixtureBook()
        let result = try BookEPUBWriter().export(
            book: book,
            chapters: [
                chapter(3, title: "三 <&>", text: "正文 & <标签>"),
                chapter(1, title: "一", text: "第一章")
            ],
            coverJPEG: nil,
            totalChapterCount: 3
        )
        defer { try? FileManager.default.removeItem(at: result.url) }
        let archive = try XCTUnwrap(Archive(url: result.url, accessMode: .read))
        let entries = Dictionary(uniqueKeysWithValues: archive.map { ($0.path, $0) })
        let first = String(decoding: try extract("OEBPS/chapter-0001.xhtml", from: archive, entries: entries), as: UTF8.self)
        let third = String(decoding: try extract("OEBPS/chapter-0002.xhtml", from: archive, entries: entries), as: UTF8.self)
        XCTAssertTrue(first.contains("第一章"))
        XCTAssertTrue(third.contains("三 &lt;&amp;&gt;"))
        XCTAssertTrue(third.contains("正文 &amp; &lt;标签&gt;"))
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

    private func chapter(_ index: Int, title: String? = nil, text: String? = nil) -> ChapterContent {
        let chapterTitle = title ?? "章节\(index)"
        return ChapterContent(
            chapter: BookChapter(title: chapterTitle, url: "fixture/\(index)",
                                 bookUrl: "fixture/book", index: index),
            title: chapterTitle,
            paragraphs: [text ?? "正文\(index)"]
        )
    }
}

private actor ExportFixtureEngine: SourceEngine {
    private(set) var requestCount = 0
    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        requestCount += 1
        return .success(ChapterContent(chapter: chapter, title: chapter.title, paragraphs: ["EXPORT-\(chapter.index)"]))
    }
    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> { .success([]) }
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> { .failure(.rule("Unused export fixture")) }
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> { .success([]) }
}
