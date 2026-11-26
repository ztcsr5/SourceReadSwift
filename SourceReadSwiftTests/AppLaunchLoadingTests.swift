import Foundation
import XCTest
@testable import SourceReadSwift

@MainActor
final class AppLaunchLoadingTests: XCTestCase {
    func testLargeLibraryLoadsOffMainAndPreservesGroupsAndProgress() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = (0..<1001).map { index in
            BookSource(bookSourceName: "书源 \(index)", bookSourceUrl: "https://launch-\(index).invalid",
                ruleContent: SourceRule(fields: ["content": String(repeating: "正文规则", count: 256)]))
        }
        try SourcePersistence(rootURL: root).save(SourceLibrarySnapshot(sources: sources))
        let shelf = BookshelfPersistence(rootURL: root)
        let book = makeBook()
        try shelf.save([book])
        var progressed = book
        progressed.currentChapterIndex = 7
        progressed.lastReadAt = Date(timeIntervalSince1970: 1_700_000_000)
        try shelf.saveReadingProgress([progressed])
        XCTAssertEqual(try shelf.load().first?.currentChapterIndex, 7, "The sidecar fixture must represent a real saved reading session")
        let groups = [BookshelfGroup(name: "后", sortOrder: 2), BookshelfGroup(name: "先", sortOrder: 1)]
        try BookshelfGroupPersistence(rootURL: root).save(groups)
        let originalSources = try Data(contentsOf: root.appendingPathComponent("book_sources.json"))
        let files = LaunchReadFileManager()
        let app = await ReaderRegressionLaunch.loadAppState(
            sourcePersistence: SourcePersistence(fileManager: files, rootURL: root),
            bookshelfPersistence: BookshelfPersistence(fileManager: files, rootURL: root),
            groupPersistence: BookshelfGroupPersistence(fileManager: files, rootURL: root))
        XCTAssertEqual(app.sourceStore.sources.count, 1001)
        XCTAssertEqual(app.sourceStore.sources.last?.ruleContent?.fields["content"], sources.last?.ruleContent?.fields["content"])
        XCTAssertEqual(app.bookshelfStore.books.first?.currentChapterIndex, 7)
        XCTAssertEqual(app.bookshelfStore.groups.map(\.name), ["先", "后"])
        XCTAssertNil(app.sourceStore.lastError)
        XCTAssertNil(app.bookshelfStore.lastError)
        XCTAssertFalse(app.hasLoadedReadingHistory)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("book_sources.json")), originalSources)
    }

    func testCorruptShelfAndSourceStayUntouchedInsteadOfBeingSeededOver() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let damaged = Data("{damaged library".utf8)
        let names = ["book_sources.json", "bookshelf_books.json"]
        for name in names { try damaged.write(to: root.appendingPathComponent(name)) }
        let app = await ReaderRegressionLaunch.loadAppState(
            sourcePersistence: SourcePersistence(rootURL: root),
            bookshelfPersistence: BookshelfPersistence(rootURL: root),
            groupPersistence: BookshelfGroupPersistence(rootURL: root))
        XCTAssertNotNil(app.sourceStore.lastError)
        XCTAssertNotNil(app.bookshelfStore.lastError)
        app.bookshelfStore.seedOnboardingBookIfNeeded(force: true)
        await app.bookshelfStore.waitForPendingWrites()
        XCTAssertTrue(app.bookshelfStore.books.isEmpty)
        for name in names { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(name)), damaged) }
    }

    func testBadGroupsDoNotDiscardAnOtherwiseValidShelf() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try BookshelfPersistence(rootURL: root).save([makeBook()])
        try Data("invalid groups".utf8).write(to: root.appendingPathComponent("bookshelf_groups.json"))
        let app = await ReaderRegressionLaunch.loadAppState(
            sourcePersistence: SourcePersistence(rootURL: root),
            bookshelfPersistence: BookshelfPersistence(rootURL: root),
            groupPersistence: BookshelfGroupPersistence(rootURL: root))
        XCTAssertEqual(app.bookshelfStore.books.map(\.id), ["launch-book"])
        XCTAssertNotNil(app.bookshelfStore.lastError)
    }

    func testConcurrentLaunchAndDocumentWaitersShareOneLoadEvenIfOneWaiterCancels() async {
        let expected = AppState(
            sourceStore: SourceStore(preloadedSources: .success(SourceLibrarySnapshot())),
            bookshelfStore: BookshelfStore(preloadedBooks: .success([makeBook()]), preloadedGroups: .success([])))
        let started = expectation(description: "Library load started")
        var release: CheckedContinuation<Void, Never>?
        var calls = 0
        let launch = AppLaunchState {
            calls += 1
            await withCheckedContinuation { release = $0; started.fulfill() }
            return expected
        }
        let first = Task { await launch.load() }
        let second = Task { await launch.load() }
        await fulfillment(of: [started], timeout: 5)
        first.cancel()
        release?.resume()
        let firstResult = await first.value
        let secondResult = await second.value
        let cachedResult = await launch.load()
        XCTAssertTrue(firstResult === expected)
        XCTAssertTrue(secondResult === expected)
        XCTAssertTrue(cachedResult === expected)
        XCTAssertTrue(launch.appState === expected)
        XCTAssertEqual(calls, 1)
    }

    func testStagedLaunchPublishesRealShelfBeforeSourcesAndProtectsTheArchive() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = SourcePersistence(rootURL: root)
        let source = BookSource(bookSourceName: "已保存书源", bookSourceUrl: "https://saved.invalid")
        try persistence.save(SourceLibrarySnapshot(sources: [source]))
        try BookshelfPersistence(rootURL: root).save([makeBook()])
        let original = try Data(contentsOf: root.appendingPathComponent("book_sources.json"))
        let files = GatedLaunchSourceFileManager()
        defer { files.releaseRead.signal() }
        let launched = expectation(description: "Real shelf appears while source read is blocked")
        var published: AppState?
        let request = Task { @MainActor in
            published = await ReaderRegressionLaunch.loadAppState(
                sourcePersistence: SourcePersistence(fileManager: files, rootURL: root),
                bookshelfPersistence: BookshelfPersistence(rootURL: root),
                groupPersistence: BookshelfGroupPersistence(rootURL: root), stagedSources: true)
            launched.fulfill()
        }
        await fulfillment(of: [launched], timeout: 5)
        guard let app = published else {
            files.releaseRead.signal()
            await request.value
            return
        }
        XCTAssertEqual(app.bookshelfStore.books.first?.id, "launch-book")
        XCTAssertTrue(app.isSourceLibraryLoading)
        XCTAssertTrue(app.sourceStore.isLoading)
        XCTAssertThrowsError(try app.sourceStore.importSources([source])) { error in
            XCTAssertEqual(error as? SourceImportError, .libraryLoading)
        }
        XCTAssertTrue(app.sourceStore.sources.isEmpty)
        XCTAssertFalse(app.sourceStore.restore(SourceLibrarySnapshot()))
        XCTAssertFalse(app.sourceStore.updateOrganization { $0.namedGroups = ["禁止提前写入"] })
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("book_sources.json")), original)
        let backupStarted = expectation(description: "Backup waits for the source archive")
        var backupCompleted = false
        let backup = Task { @MainActor in
            backupStarted.fulfill()
            await app.awaitSourcesReady()
            backupCompleted = true
            return app.sourceStore.backupSnapshot()
        }
        await fulfillment(of: [backupStarted], timeout: 5)
        XCTAssertFalse(backupCompleted, "An early backup must not snapshot the temporary empty source library")
        files.releaseRead.signal()
        await app.awaitSourcesReady()
        let backupSnapshot = await backup.value
        XCTAssertFalse(app.isSourceLibraryLoading)
        XCTAssertFalse(app.sourceStore.isLoading)
        XCTAssertNil(app.sourceStore.lastError)
        XCTAssertEqual(app.sourceStore.sources.map(\.bookSourceUrl), [source.bookSourceUrl])
        XCTAssertEqual(backupSnapshot.sources.map(\.bookSourceUrl), [source.bookSourceUrl])
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("book_sources.json")), original)
    }

    func testStagedSourceFailureRetainsTheShelfAndReportsTheReadError() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let damaged = Data("{broken-source".utf8)
        try damaged.write(to: root.appendingPathComponent("book_sources.json"))
        try BookshelfPersistence(rootURL: root).save([makeBook()])
        let app = await ReaderRegressionLaunch.loadAppState(sourcePersistence: SourcePersistence(rootURL: root),
            bookshelfPersistence: BookshelfPersistence(rootURL: root),
            groupPersistence: BookshelfGroupPersistence(rootURL: root), stagedSources: true)
        await app.awaitSourcesReady()
        XCTAssertEqual(app.bookshelfStore.books.first?.id, "launch-book")
        XCTAssertFalse(app.isSourceLibraryLoading)
        XCTAssertNotNil(app.sourceStore.lastError)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("book_sources.json")), damaged)
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("launch-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeBook() -> BookshelfBook {
        BookshelfBook(id: "launch-book", title: "首帧书库", author: "纸间", coverURL: nil,
            sourceName: "本地", sourceURL: "local://text", bookURL: "local://launch-book", intro: nil)
    }
}

private final class LaunchReadFileManager: FileManager, @unchecked Sendable {
    override func fileExists(atPath path: String) -> Bool {
        XCTAssertFalse(Thread.isMainThread, "Launch library I/O must not block the first frame")
        return super.fileExists(atPath: path)
    }
}

private final class GatedLaunchSourceFileManager: FileManager, @unchecked Sendable {
    let releaseRead = DispatchSemaphore(value: 0)

    override func fileExists(atPath path: String) -> Bool {
        XCTAssertFalse(Thread.isMainThread)
        _ = releaseRead.wait(timeout: .now() + 10)
        return super.fileExists(atPath: path)
    }
}
