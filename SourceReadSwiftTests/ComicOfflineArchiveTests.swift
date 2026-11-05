import XCTest
@testable import SourceReadSwift

final class ComicOfflineArchiveTests: XCTestCase {
    private let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAIAAAASFvFNAAAAGklEQVR42mNgYGhg0ADiACBmCACygTggoAEAMGgE4bJ9Q/wAAAAASUVORK5CYII=")!

    func testCommittedChapterReopensWithoutNetworkAndSurvivesOrdinaryCacheClear() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = ComicOfflineArchive(directory: root.appendingPathComponent("comics"))
        let content = chapter()
        let requests = OfflineComicRequestProbe(bytes: image)
        try await archive.save(content, sourceURL: "https://source.invalid", headers: ["Cookie": "test-context"]) {
            await requests.fetch($0)
        }
        let stored = await archive.pages(sourceURL: "https://source.invalid", chapter: content.chapter)
        let pages = try XCTUnwrap(stored)
        XCTAssertEqual(pages.map(\.id), [0, 1])
        for page in pages {
            let url = try XCTUnwrap(URL(string: page.url))
            XCTAssertTrue(url.isFileURL)
            XCTAssertEqual(try Data(contentsOf: url), image)
        }
        let snapshot = await requests.requests
        XCTAssertEqual(snapshot.map(\.url), ["https://cdn.invalid/one.png", "https://cdn.invalid/two.png"])
        XCTAssertEqual(snapshot.last?.headers["Cookie"], "test-context")
        XCTAssertEqual(snapshot.first?.headers["Referer"], content.chapter.url)

        let cache = await ChapterContentCacheStore(persistence: ChapterContentCachePersistence(rootURL: root))
        await cache.save(content, sourceURL: "https://source.invalid", purifyRules: [])
        await cache.removeAll()
        let reopened = ComicOfflineArchive(directory: root.appendingPathComponent("comics"))
        let isPresent = await reopened.contains(sourceURL: "https://source.invalid", chapter: content.chapter)
        XCTAssertTrue(isPresent)
        let otherSource = await reopened.pages(sourceURL: "https://other-source.invalid", chapter: content.chapter)
        XCTAssertNil(otherSource)

        let toc = await reopened.chapters(sourceURL: "https://source.invalid", bookURL: content.chapter.bookUrl)
        XCTAssertEqual(toc.map(\.index), [7])
        XCTAssertTrue(ComicOfflineArchive.isOfflineChapter(try XCTUnwrap(toc.first)))
        let fromToken = await reopened.pages(sourceURL: "https://source.invalid", chapter: toc[0])
        XCTAssertEqual(fromToken, pages)

        let manifestURL = try XCTUnwrap(URL(string: pages[0].url)).deletingLastPathComponent().appendingPathComponent("chapter.json")
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        XCTAssertFalse(manifest.contains("test-context"))
        XCTAssertFalse(manifest.contains("https://cdn.invalid"))
        XCTAssertFalse(manifest.contains("Cookie"))
    }

    func testPartialOrCorruptDownloadIsNotACommittedChapterAndCanBeRetried() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = ComicOfflineArchive(directory: root)
        let content = chapter()
        let requests = OfflineComicRequestProbe(bytes: image, failsSecondPage: true)
        do {
            try await archive.save(content, sourceURL: "source", headers: [:]) { await requests.fetch($0) }
            XCTFail("A failed page must fail the chapter download")
        } catch let error as ComicOfflineArchive.Failure {
            guard case .page(2, .http(422)) = error else { return XCTFail("Unexpected failure: \(error)") }
        }
        let partial = await archive.pages(sourceURL: "source", chapter: content.chapter)
        XCTAssertNil(partial)
        await requests.allowAllPages()
        try await archive.save(content, sourceURL: "source", headers: [:]) { await requests.fetch($0) }
        let saved = await archive.pages(sourceURL: "source", chapter: content.chapter)
        let page = try XCTUnwrap(saved?.first)
        let pageURL = try XCTUnwrap(URL(string: page.url))
        var corrupt = try Data(contentsOf: pageURL)
        corrupt[corrupt.count - 1] ^= 1
        try corrupt.write(to: pageURL)
        let isComplete = await archive.contains(sourceURL: "source", chapter: content.chapter)
        let corrupted = await archive.pages(sourceURL: "source", chapter: content.chapter)
        XCTAssertFalse(isComplete, "The same byte count cannot hide image corruption")
        XCTAssertNil(corrupted)
    }

    func testClearDuringSuspendedDownloadCannotResurrectFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = ComicOfflineArchive(directory: root)
        let held = HeldOfflineComicPage()
        let content = chapter()
        let download = Task {
            try await archive.save(content, sourceURL: "source", headers: [:]) { _ in await held.fetch() }
        }
        for _ in 0..<200 {
            let hasRequest = await held.hasRequest
            if hasRequest { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let started = await held.hasRequest
        XCTAssertTrue(started)
        try await archive.removeAll()
        await held.release(image)
        do { try await download.value; XCTFail("Clearing invalidates the pending commit") }
        catch is CancellationError {}
        let saved = await archive.pages(sourceURL: "source", chapter: content.chapter)
        XCTAssertNil(saved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testUnfinishedPaginationAndSparseChapterPositionsStayExplicit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = ComicOfflineArchive(directory: root)
        let original = chapter()
        let unfinished = ChapterContent(chapter: original.chapter, title: original.title,
                                        paragraphs: original.paragraphs, nextContentUrl: "/next-page")
        do {
            try await archive.save(unfinished, sourceURL: "source", headers: [:]) { _ in
                XCTFail("Do not fetch images for an unfinished chapter")
                return .failure(.cancelled)
            }
            XCTFail("A readable prefix is not an offline chapter")
        } catch let error as ComicOfflineArchive.Failure {
            guard case .incompleteChapter = error else { return XCTFail("Unexpected failure: \(error)") }
        }
        let chapters = [7, 11].map { BookChapter(title: "\($0)", url: "offline-\($0)", bookUrl: "book", index: $0) }
        XCTAssertEqual(ComicPagePositionPolicy.chapterOffset(7, in: chapters), 0)
        XCTAssertEqual(ComicPagePositionPolicy.chapterOffset(11, in: chapters), 1)
    }

    private func chapter() -> ChapterContent {
        let chapter = BookChapter(title: "第八话", url: "https://comic.invalid/chapter/7", bookUrl: "https://comic.invalid/book", index: 7)
        return ChapterContent(chapter: chapter, title: chapter.title,
                              paragraphs: [#"["https://cdn.invalid/one.png","https://cdn.invalid/two.png"]"#])
    }
}

private actor OfflineComicRequestProbe {
    private let bytes: Data
    private var failsSecondPage: Bool
    private(set) var requests: [ComicImageRequest] = []
    init(bytes: Data, failsSecondPage: Bool = false) {
        self.bytes = bytes
        self.failsSecondPage = failsSecondPage
    }
    func allowAllPages() { failsSecondPage = false }
    func fetch(_ request: ComicImageRequest) -> Result<Data, ComicImageFailure> {
        requests.append(request)
        if failsSecondPage && request.url.hasSuffix("two.png") { return .failure(.http(422)) }
        return .success(bytes)
    }
}

private actor HeldOfflineComicPage {
    private var continuation: CheckedContinuation<Result<Data, ComicImageFailure>, Never>?
    var hasRequest: Bool { continuation != nil }
    func fetch() async -> Result<Data, ComicImageFailure> {
        await withCheckedContinuation { continuation = $0 }
    }
    func release(_ bytes: Data) {
        continuation?.resume(returning: .success(bytes))
        continuation = nil
    }
}
