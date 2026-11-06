import UIKit
import XCTest
import ZIPFoundation
@testable import SourceReadSwift

final class LocalComicBookParserTests: XCTestCase {
    func testNaturalPageOrderSurvivesShelfEncodingAndUsesTheNativeComicEngine() async throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("漫画.cbz")
        let archive = try XCTUnwrap(Archive(url: file, accessMode: .create))
        let first = try page(.blue), second = try page(.red)
        try add("pages/10.png", bytes: second, to: archive)
        try add("pages/2.png", bytes: first, to: archive)
        try add("__MACOSX/._1.png", bytes: Data("metadata".utf8), to: archive)
        let parsed = try LocalComicBookParser(directory: root.appendingPathComponent("imports")).parse(fileURL: file)
        XCTAssertEqual(parsed.mediaKind, .comic)
        let original = BookshelfBook(localTextBook: parsed)
        let book = try JSONDecoder().decode(BookshelfBook.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(book.sourceURL, "local://comic")
        let engine = LocalComicSourceEngine(book: book)
        let chapter = try XCTUnwrap(engine.chapters.first)
        let content = try await engine.getContent(source: LocalComicSourceEngine.source, chapter: chapter).get()
        XCTAssertEqual(content.paragraphs.count, 2)
        XCTAssertTrue(ComicContentParser.parsePages(from: content).isEmpty,
                      "Network rules must not gain local-file access from CBZ support")
        let pages = engine.pages(for: chapter)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(URL(string: pages[0].url))), first)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(URL(string: pages[1].url))), second)
        XCTAssertTrue(pages.allSatisfy { URL(string: $0.url)?.isFileURL == true })
        let firstURL = try XCTUnwrap(URL(string: pages[0].url))
        let decoded = await RemoteImageLoader.shared.comicPage(for: firstURL, headers: [:], maxPixelSize: 64)
        guard case .success(let bitmap) = decoded else { return XCTFail("The imported page must decode in the production pipeline") }
        XCTAssertGreaterThan(bitmap.size.height, 0)
    }

    func testBadImageRollsBackTheWholeImportInsteadOfCommittingAPrefix() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("broken.cbz")
        let archive = try XCTUnwrap(Archive(url: file, accessMode: .create))
        try add("1.png", bytes: page(.white), to: archive)
        try add("2.png", bytes: Data("not an image".utf8), to: archive)
        let imports = root.appendingPathComponent("imports")
        XCTAssertThrowsError(try LocalComicBookParser(directory: imports).parse(fileURL: file))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: imports.path), [])
    }

    func testUnsafePathsAndPageCountLimitAreRejected() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("unsafe.cbz")
        let archive = try XCTUnwrap(Archive(url: file, accessMode: .create))
        let bitmap = try page(.white)
        try add("../escape.png", bytes: bitmap, to: archive)
        XCTAssertThrowsError(try LocalComicBookParser(directory: root.appendingPathComponent("imports")).parse(fileURL: file))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escape.png").path))
        let large = root.appendingPathComponent("too-many.cbz")
        let many = try XCTUnwrap(Archive(url: large, accessMode: .create))
        for index in 0...600 { try add("\(index).png", bytes: bitmap, to: many) }
        XCTAssertThrowsError(try LocalComicBookParser(directory: root.appendingPathComponent("imports")).parse(fileURL: large))
    }

    func testDeletionIsConfinedToTheImportedComicDirectory() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sample.cbz")
        let archive = try XCTUnwrap(Archive(url: file, accessMode: .create))
        try add("1.png", bytes: page(.white), to: archive)
        let imports = root.appendingPathComponent("imports")
        let parsed = try LocalComicBookParser(directory: imports).parse(fileURL: file)
        var book = BookshelfBook(localTextBook: parsed)
        let cover = try XCTUnwrap(parsed.coverURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cover.path))
        let unrelated = root.appendingPathComponent("keep.png")
        try Data("keep".utf8).write(to: unrelated)
        book.coverURL = unrelated.absoluteString
        try LocalComicBookParser.removeFiles(for: book, directory: imports)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        book.coverURL = cover.absoluteString
        try LocalComicBookParser.removeFiles(for: book, directory: imports)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cover.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testIncorrectArchiveChecksumCannotCommitAnOtherwiseDecodablePage() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("checksum.cbz")
        let archive = try XCTUnwrap(Archive(url: file, accessMode: .create))
        try add("1.png", bytes: page(.white), to: archive)
        var bytes = try Data(contentsOf: file)
        let directoryEntry = try XCTUnwrap(bytes.range(of: Data([0x50, 0x4b, 0x01, 0x02])))
        let checksumOffset = directoryEntry.lowerBound + 16
        bytes.replaceSubrange(checksumOffset..<(checksumOffset + 4), with: [0, 0, 0, 0])
        try bytes.write(to: file, options: .atomic)
        let imports = root.appendingPathComponent("imports")
        XCTAssertThrowsError(try LocalComicBookParser(directory: imports).parse(fileURL: file))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: imports.path), [])
    }

    private func makeFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func page(_ color: UIColor) throws -> Data {
        let bitmap = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 48)).image { renderer in
            color.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 24, height: 48))
        }
        return try XCTUnwrap(bitmap.pngData())
    }

    private func add(_ path: String, bytes: Data, to archive: Archive) throws {
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(bytes.count)) { position, count in
            bytes.subdata(in: Int(position)..<(Int(position) + count))
        }
    }
}
