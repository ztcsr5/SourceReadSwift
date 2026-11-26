import XCTest
@testable import SourceReadSwift

final class ComicChapterWindowTests: XCTestCase {
    func testSplicingRetainsOrderAndTheWindowIsBoundedDuringForwardAndReverseReading() {
        var window = ComicStripChapterWindow()
        window.reset(to: chapter(2))
        XCTAssertTrue(window.stitch(chapter(1), around: 2))
        XCTAssertTrue(window.stitch(chapter(3), around: 2))
        XCTAssertEqual(window.chapters.map(\.offset), [1, 2, 3])
        XCTAssertEqual(window.snapshot.indices[.init(chapterOffset: 2, pageIndex: 1)], 3)
        XCTAssertFalse(window.stitch(chapter(3), around: 2), "Do not mount a duplicate chapter from a late response")
        XCTAssertFalse(window.stitch(chapter(5), around: 3), "Do not skip a missing neighbour")

        XCTAssertTrue(window.stitch(chapter(4), around: 3))
        XCTAssertEqual(window.chapters.map(\.offset), [2, 3, 4])
        XCTAssertTrue(window.stitch(chapter(1), around: 2))
        XCTAssertEqual(window.chapters.map(\.offset), [1, 2, 3])
        XCTAssertTrue(window.prune(around: 2, includesNeighbours: false))
        XCTAssertEqual(window.chapters.map(\.offset), [2])
    }

    func testIncompleteChapterBlocksContinuationInBothDirections() {
        var window = ComicStripChapterWindow()
        window.reset(to: chapter(0, partial: true))
        XCTAssertFalse(window.stitch(chapter(1), around: 0))
        window.reset(to: chapter(1))
        XCTAssertFalse(window.stitch(chapter(0, partial: true), around: 1))
        XCTAssertFalse(window.stitch(chapter(2, partial: true), around: 1))
        XCTAssertEqual(window.chapters.map(\.offset), [1])
    }

    func testSpeculativePageRequestsAreDirectionalAndBounded() {
        XCTAssertEqual(ComicPagePositionPolicy.prefetchOrder(around: 5, count: 20, direction: -1, depth: 2), [4, 3, 6])
        XCTAssertEqual(ComicPagePositionPolicy.prefetchOrder(around: 0, count: 3, direction: 1, depth: 500), [1, 2])
        XCTAssertEqual(ComicPagePositionPolicy.prefetchOrder(around: 0, count: 3, direction: 1, depth: 0), [])
    }

    @MainActor
    func testPagePrefetchRetainsOverlappingTransfersAndDrainsTheNearestPendingPage() async throws {
        let queue = ComicPageLoadQueue<Int>()
        let probe = ComicPageLoadProbe()
        defer { queue.cancelAll(); probe.releaseAll() }
        queue.update(visible: [], prefetch: [1, 2, 3, 4]) { await probe.load($0) }
        try await waitForPageLoads { Set(probe.started) == [1, 2] }
        XCTAssertEqual(probe.waitingPages.count, 2)

        queue.update(visible: [], prefetch: [2, 3, 4]) { await probe.load($0) }
        try await waitForPageLoads { probe.cancelled.contains(1) && probe.started.contains(3) }
        XCTAssertEqual(probe.started.filter { $0 == 2 }.count, 1, "The overlapping page must keep its original transfer")
        XCTAssertFalse(probe.cancelled.contains(2))
        XCTAssertFalse(probe.started.contains(4))
        probe.complete(2)
        try await waitForPageLoads { probe.started.contains(4) }
        XCTAssertLessThanOrEqual(probe.waitingPages.count, 2)
    }

    @MainActor
    func testVisiblePagesPreemptOnlyTheFarthestSpeculationAndKeepTheFourLoadLimit() async throws {
        let queue = ComicPageLoadQueue<Int>()
        let probe = ComicPageLoadProbe()
        defer { queue.cancelAll(); probe.releaseAll() }
        queue.update(visible: [0, 1], prefetch: [2, 3, 4, 5]) { await probe.load($0) }
        try await waitForPageLoads { probe.waitingPages == [0, 1, 2, 3] }
        queue.update(visible: [0, 1, 4], prefetch: [2, 3, 5]) { await probe.load($0) }
        try await waitForPageLoads { probe.started.contains(4) && probe.cancelled.contains(3) }
        XCTAssertEqual(probe.waitingPages, [0, 1, 2, 4])
        XCTAssertFalse(probe.cancelled.contains(2), "Keep the nearer overlapping speculative transfer")
        XCTAssertFalse(probe.started.contains(5), "A visible page gets the available slot before farther speculation")
    }

    @MainActor
    func testDepartingVisiblePagesReleaseTheFarthestLoadToKeepThePrefetchLimit() async throws {
        let queue = ComicPageLoadQueue<Int>()
        let probe = ComicPageLoadProbe()
        defer { queue.cancelAll(); probe.releaseAll() }
        queue.update(visible: [0, 1, 2, 3], prefetch: []) { await probe.load($0) }
        try await waitForPageLoads { probe.waitingPages == [0, 1, 2, 3] }

        queue.update(visible: [3], prefetch: [2, 1, 0, 4]) { await probe.load($0) }
        try await waitForPageLoads { probe.cancelled.contains(0) && probe.waitingPages == [1, 2, 3] }
        XCTAssertFalse(probe.cancelled.contains(1) || probe.cancelled.contains(2))
        XCTAssertFalse(probe.started.contains(4), "Keep only the two nearest speculative transfers after visible pages leave the viewport")

        queue.update(visible: [3, 5], prefetch: [2, 1, 0, 4]) { await probe.load($0) }
        try await waitForPageLoads { probe.waitingPages == [1, 2, 3, 5] }
        XCTAssertFalse(probe.cancelled.contains(1) || probe.cancelled.contains(2),
                       "The reserved visible slot must not need another speculative cancellation")
    }

    @MainActor
    func testReversingChangingChapterAndClosingRetireOnlyDepartingPageLoads() async throws {
        let queue = ComicPageLoadQueue<Int>()
        let probe = ComicPageLoadProbe()
        defer { queue.cancelAll(); probe.releaseAll() }
        queue.update(visible: [], prefetch: [5, 6, 7]) { await probe.load($0) }
        try await waitForPageLoads { probe.waitingPages == [5, 6] }
        queue.update(visible: [], prefetch: [4, 3, 5]) { await probe.load($0) }
        try await waitForPageLoads { probe.waitingPages == [4, 5] }
        XCTAssertFalse(probe.cancelled.contains(5))
        XCTAssertFalse(probe.started.contains(7))
        queue.update(visible: [], prefetch: [100, 101]) { await probe.load($0) }
        try await waitForPageLoads { probe.waitingPages == [100, 101] }
        XCTAssertTrue(probe.cancelled.contains(4) && probe.cancelled.contains(5))
        queue.cancelAll()
        try await waitForPageLoads { probe.waitingPages.isEmpty }
        XCTAssertTrue(probe.cancelled.contains(100) && probe.cancelled.contains(101))
    }

    @MainActor
    func testACompletedSpeculativeAttemptDoesNotPreventTheLaterVisibleAttempt() async throws {
        let queue = ComicPageLoadQueue<Int>()
        let probe = ComicPageLoadProbe()
        defer { queue.cancelAll(); probe.releaseAll() }
        queue.update(visible: [], prefetch: [1]) { await probe.load($0) }
        try await waitForPageLoads { probe.waitingPages == [1] }
        probe.complete(1)
        try await waitForPageLoads { probe.finished.contains(1) }
        queue.update(visible: [1], prefetch: []) { await probe.load($0) }
        try await waitForPageLoads { probe.started.filter { $0 == 1 }.count == 2 }
    }

    @MainActor
    private func waitForPageLoads(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Page load scheduling did not settle within two seconds")
    }

    private func chapter(_ index: Int, partial: Bool = false) -> ComicStripChapter {
        let chapter = BookChapter(title: "Fixture", url: "https://comic.example/chapter/\(index)",
                                  bookUrl: "https://comic.example/book", index: index)
        let paragraphs = (1...2).map { "[img]https://comic.example/\(index)/\($0).png[/img]" }
        let content = ChapterContent(chapter: chapter, title: chapter.title, paragraphs: paragraphs,
                                     nextContentUrl: partial ? "https://comic.example/next" : nil)
        let resources = ComicChapterResources(content: content)
        return ComicStripChapter(offset: index, resources: resources,
            requests: resources.pages.map { ComicImageRequest(url: $0.url, headers: $0.headers) })
    }
}

@MainActor
final class ComicPageLoadProbe {
    private struct Pending { let page: Int; let continuation: CheckedContinuation<Void, Never> }
    private var pending: [UUID: Pending] = [:]
    private(set) var started: [Int] = []
    private(set) var cancelled: [Int] = []
    private(set) var finished: [Int] = []
    var waitingPages: Set<Int> { Set(pending.values.map(\.page)) }

    func load(_ page: Int) async {
        let id = UUID()
        started.append(page)
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                if Task.isCancelled { continuation.resume(); return }
                pending[id] = Pending(page: page, continuation: continuation)
            }
        }, onCancel: {
            Task { @MainActor in
                guard let waiting = self.pending.removeValue(forKey: id) else { return }
                self.cancelled.append(page)
                waiting.continuation.resume()
            }
        })
        finished.append(page)
    }

    func complete(_ page: Int) {
        guard let id = pending.first(where: { $0.value.page == page })?.key else { return }
        pending.removeValue(forKey: id)?.continuation.resume()
    }

    func releaseAll() {
        let waiting = pending.values
        pending.removeAll()
        for item in waiting { item.continuation.resume() }
    }
}
