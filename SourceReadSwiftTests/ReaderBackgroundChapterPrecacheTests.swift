import XCTest
@testable import SourceReadSwift

@MainActor
final class ReaderBackgroundChapterPrecacheTests: XCTestCase {
    private actor LoadCounter {
        var active = 0
        var peak = 0
        var completed = 0

        func begin() {
            active += 1
            peak = max(peak, active)
        }

        func finish() {
            active -= 1
            completed += 1
        }
    }

    func testSharedSpeculativeBudgetKeepsOnlyTwoOperationsInFlight() async {
        let budget = ReaderChapterPrefetchBudget(limit: 2)
        let counter = LoadCounter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    _ = await budget.withSlot {
                        await counter.begin()
                        try? await Task.sleep(nanoseconds: 2_000_000)
                        await counter.finish()
                    }
                }
            }
        }
        let peak = await counter.peak
        let completed = await counter.completed
        XCTAssertLessThanOrEqual(peak, 2)
        XCTAssertEqual(completed, 12)
    }

    private func chapter(_ index: Int) -> BookChapter {
        BookChapter(title: "第 \(index) 章", url: "https://fixture.invalid/\(index)",
                    bookUrl: "https://fixture.invalid/book", index: index)
    }

    private func waitForTakeover(_ chapter: BookChapter, queue: ReaderBackgroundChapterPrecache) async -> Bool {
        for _ in 0..<200 {
            if !queue.hasPendingLoad(for: chapter) { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    func testRepeatedNearBoundarySignalsDoNotLaunchDuplicateLoads() async {
        let queue = ReaderBackgroundChapterPrecache()
        let started = expectation(description: "first request started")
        let saved = expectation(description: "first request committed")
        var release: CheckedContinuation<Result<ChapterContent, SourceEngineError>?, Never>?
        var requests = 0
        var commits = 0
        let target = chapter(4)
        let load: @MainActor (BookChapter) async -> Result<ChapterContent, SourceEngineError>? = { _ in
            requests += 1
            return await withCheckedContinuation { continuation in
                release = continuation
                started.fulfill()
            }
        }
        let commit: @MainActor (ChapterContent) -> Void = { _ in commits += 1; saved.fulfill() }
        queue.start(key: "window-5", chapters: [target], load: load, commit: commit)
        await fulfillment(of: [started], timeout: 2)
        for _ in 0..<10 { queue.start(key: "window-5", chapters: [target], load: load, commit: commit) }
        release?.resume(returning: .success(ChapterContent(chapter: target, title: target.title, paragraphs: ["正文"])))
        await fulfillment(of: [saved], timeout: 2)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(commits, 1)
        queue.cancel()
    }

    func testForegroundTakesOverTheSameChapterWithoutRestartingOrCancellingItsRequest() async {
        let queue = ReaderBackgroundChapterPrecache()
        let started = expectation(description: "background chapter started")
        var release: CheckedContinuation<Result<ChapterContent, SourceEngineError>?, Never>?
        var requested: [Int] = []
        var committed: [Int] = []
        var wasCancelled = false
        let target = chapter(4)
        queue.start(key: "old-window", chapters: [target, chapter(3)], load: { chapter in
            requested.append(chapter.index)
            let result = await withCheckedContinuation { continuation in
                release = continuation; started.fulfill()
            }
            wasCancelled = Task.isCancelled
            return result
        }, commit: { committed.append($0.chapter.index) })
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(queue.hasPendingLoad(for: target))
        let foreground = Task { @MainActor in await queue.takePendingResult(for: target) }
        let transferred = await waitForTakeover(target, queue: queue)
        XCTAssertTrue(transferred)
        queue.cancel()
        release?.resume(returning: .success(ChapterContent(chapter: target, title: target.title, paragraphs: ["正文"])))
        let result = await foreground.value
        guard case .success(let content)? = result else { return XCTFail("Foreground must reuse the pending result") }
        XCTAssertEqual(content.chapter, target)
        XCTAssertEqual(requested, [4])
        XCTAssertTrue(committed.isEmpty, "The cancelled background queue must not save or continue")
        XCTAssertFalse(wasCancelled, "Foreground ownership outlives cancellation of the old background queue")
    }

    func testForegroundReceivesPendingBlockedFailureWithoutAnotherRequest() async {
        let queue = ReaderBackgroundChapterPrecache()
        let started = expectation(description: "background chapter started")
        var release: CheckedContinuation<Result<ChapterContent, SourceEngineError>?, Never>?
        var requests = 0
        let target = chapter(4)
        // Synthetic notice, not a captured response from a live source.
        let failure = SourceEngineError.blocked("访问过快，请在1分钟后重试")
        queue.start(key: "window", chapters: [target], load: { _ in
            requests += 1
            return await withCheckedContinuation { continuation in
                release = continuation; started.fulfill()
            }
        }, commit: { _ in XCTFail("A blocked result must not be saved") })
        await fulfillment(of: [started], timeout: 2)
        let foreground = Task { @MainActor in await queue.takePendingResult(for: target) }
        let transferred = await waitForTakeover(target, queue: queue)
        XCTAssertTrue(transferred)
        release?.resume(returning: .failure(failure))
        let result = await foreground.value
        guard case .failure(let received)? = result else { return XCTFail("Foreground must receive the original failure") }
        XCTAssertEqual(received, failure)
        XCTAssertEqual(requests, 1)
        queue.cancel()
    }

    func testCancellingForegroundTakeoverCancelsItsRequest() async {
        let queue = ReaderBackgroundChapterPrecache()
        let started = expectation(description: "background chapter started")
        var release: CheckedContinuation<Result<ChapterContent, SourceEngineError>?, Never>?
        var wasCancelled = false
        let target = chapter(4)
        queue.start(key: "window", chapters: [target], load: { _ in
            let result = await withCheckedContinuation { continuation in
                release = continuation; started.fulfill()
            }
            wasCancelled = Task.isCancelled
            return result
        }, commit: { _ in XCTFail("A cancelled request must not be committed") })
        await fulfillment(of: [started], timeout: 2)
        let foreground = Task { @MainActor in await queue.takePendingResult(for: target) }
        let transferred = await waitForTakeover(target, queue: queue)
        XCTAssertTrue(transferred)
        foreground.cancel()
        release?.resume(returning: .failure(.network("cancelled")))
        _ = await foreground.value
        XCTAssertTrue(wasCancelled)
        queue.cancel()
    }

    func testBlockedResultStopsTheRemainingBackgroundQueue() async {
        let queue = ReaderBackgroundChapterPrecache()
        let first = expectation(description: "first chapter returned a block")
        let next = expectation(description: "no further request after a block")
        next.isInverted = true
        // Synthetic server failure; no request is sent to a real source.
        queue.start(key: "blocked", chapters: [chapter(4), chapter(3)], load: { chapter in
            if chapter.index == 4 { first.fulfill() } else { next.fulfill() }
            return .failure(.blocked("请求过于频繁，请稍后重试"))
        }, commit: { _ in XCTFail("A block must not be saved") })
        await fulfillment(of: [first, next], timeout: 0.05)
        queue.cancel()
    }

    func testOneEmptyChapterDoesNotStopOtherBackgroundChapters() async {
        let queue = ReaderBackgroundChapterPrecache()
        let saved = expectation(description: "later chapter saved")
        queue.start(key: "missing-one", chapters: [chapter(4), chapter(3)], load: { chapter in
            if chapter.index == 4 { return .failure(.empty("正文为空")) }
            return .success(ChapterContent(chapter: chapter, title: chapter.title, paragraphs: ["正文"]))
        }, commit: { content in XCTAssertEqual(content.chapter.index, 3); saved.fulfill() })
        await fulfillment(of: [saved], timeout: 2)
        queue.cancel()
    }

    func testOneMissingChapterDoesNotStopOtherBackgroundChapters() async {
        let queue = ReaderBackgroundChapterPrecache()
        let saved = expectation(description: "later chapter saved after a 404")
        queue.start(key: "missing-one", chapters: [chapter(4), chapter(3)], load: { chapter in
            if chapter.index == 4 { return .failure(.network("HTTP 404")) }
            return .success(ChapterContent(chapter: chapter, title: chapter.title, paragraphs: ["正文"]))
        }, commit: { content in XCTAssertEqual(content.chapter.index, 3); saved.fulfill() })
        await fulfillment(of: [saved], timeout: 2)
        queue.cancel()
    }

    func testSourcePauseStopsBothQueuesWithoutCancellingTheForegroundOwner() async {
        let queue = ReaderBackgroundChapterPrecache()
        let mounted = ReaderPrefetchState()
        mounted.queue = [5, 6]
        let started = expectation(description: "background request started")
        var release: CheckedContinuation<Result<ChapterContent, SourceEngineError>?, Never>?
        var wasCancelled = false
        var requested: [Int] = []
        let target = chapter(4)
        queue.start(key: "window", chapters: [target, chapter(3)], load: { chapter in
            requested.append(chapter.index)
            let result = await withCheckedContinuation { continuation in
                release = continuation; started.fulfill()
            }
            wasCancelled = Task.isCancelled
            return result
        }, commit: { _ in XCTFail("A foreground-owned request must not be committed by the old queue") })
        await fulfillment(of: [started], timeout: 2)
        let foreground = Task { @MainActor in await queue.takePendingResult(for: target) }
        let transferred = await waitForTakeover(target, queue: queue)
        XCTAssertTrue(transferred)

        if mounted.pauseRequests(after: .network("HTTP 429")) { queue.cancel() }
        XCTAssertNil(mounted.nextChapter())
        XCTAssertTrue(mounted.queue.isEmpty)
        release?.resume(returning: .success(ChapterContent(chapter: target, title: target.title, paragraphs: ["正文"])))
        let result = await foreground.value
        guard case .success? = result else { return XCTFail("The foreground owner must retain its result") }
        XCTAssertFalse(wasCancelled)
        XCTAssertEqual(requested, [4])
    }

    func testSourcePauseLetsAnAlreadyStartedMountedRequestFinish() async {
        let mounted = ReaderPrefetchState()
        let started = expectation(description: "mounted request started")
        var release: CheckedContinuation<Void, Never>?
        var wasCancelled = false
        mounted.queue = [5, 6]
        let request = Task { @MainActor in
            await withCheckedContinuation { continuation in
                release = continuation; started.fulfill()
            }
            wasCancelled = Task.isCancelled
        }
        mounted.task = request
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(mounted.pauseRequests(after: .blocked("请求过于频繁，请稍后重试")))
        XCTAssertNil(mounted.nextChapter())
        release?.resume()
        await request.value
        XCTAssertFalse(wasCancelled)
        XCTAssertFalse(request.isCancelled)
    }

    func testChapterTakeoverDoesNotCrossBookIdentity() async {
        let queue = ReaderBackgroundChapterPrecache()
        let started = expectation(description: "original book started")
        let saved = expectation(description: "original book saved")
        var release: CheckedContinuation<Result<ChapterContent, SourceEngineError>?, Never>?
        let target = chapter(4)
        let otherBook = BookChapter(title: target.title, url: target.url, bookUrl: "https://fixture.invalid/other", index: target.index)
        queue.start(key: "original-book", chapters: [target], load: { _ in
            await withCheckedContinuation { continuation in release = continuation; started.fulfill() }
        }, commit: { _ in saved.fulfill() })
        await fulfillment(of: [started], timeout: 2)
        XCTAssertFalse(queue.hasPendingLoad(for: otherBook))
        let unrelated = await queue.takePendingResult(for: otherBook)
        XCTAssertNil(unrelated)
        XCTAssertTrue(queue.hasPendingLoad(for: target))
        release?.resume(returning: .success(ChapterContent(chapter: target, title: target.title, paragraphs: ["正文"])))
        await fulfillment(of: [saved], timeout: 2)
        queue.cancel()
    }

    func testLeavingReaderRejectsAnUncooperativeLateLoadAndStopsRemainingChapters() async {
        let queue = ReaderBackgroundChapterPrecache()
        let started = expectation(description: "request started")
        let returned = expectation(description: "cancelled request returned")
        var release: CheckedContinuation<Result<ChapterContent, SourceEngineError>?, Never>?
        var requests: [Int] = []
        var committed: [Int] = []
        let target = chapter(4)
        queue.start(key: "old-window", chapters: [target, chapter(3)], load: { chapter in
            requests.append(chapter.index)
            let content = await withCheckedContinuation { continuation in
                release = continuation
                started.fulfill()
            }
            returned.fulfill()
            return content
        }, commit: { committed.append($0.chapter.index) })
        await fulfillment(of: [started], timeout: 2)
        queue.cancel()
        release?.resume(returning: .success(ChapterContent(chapter: target, title: target.title, paragraphs: ["迟到正文"])))
        await fulfillment(of: [returned], timeout: 2)
        await Task.yield()
        XCTAssertEqual(requests, [4])
        XCTAssertTrue(committed.isEmpty)
    }

    func testNewWindowOwnsItsResultsWhenPreviousWindowCompletesLast() async {
        let queue = ReaderBackgroundChapterPrecache()
        let started = expectation(description: "old window started")
        let saved = expectation(description: "new window saved")
        let returned = expectation(description: "old window returned")
        var release: CheckedContinuation<Result<ChapterContent, SourceEngineError>?, Never>?
        var committed: [Int] = []
        let old = chapter(4), next = chapter(14)
        queue.start(key: "old", chapters: [old], load: { _ in
            let content = await withCheckedContinuation { continuation in
                release = continuation; started.fulfill()
            }
            returned.fulfill()
            return content
        }, commit: { committed.append($0.chapter.index) })
        await fulfillment(of: [started], timeout: 2)
        queue.start(key: "new", chapters: [next], load: { chapter in
            .success(ChapterContent(chapter: chapter, title: chapter.title, paragraphs: ["新正文"]))
        }, commit: { committed.append($0.chapter.index); saved.fulfill() })
        await fulfillment(of: [saved], timeout: 2)
        release?.resume(returning: .success(ChapterContent(chapter: old, title: old.title, paragraphs: ["旧正文"])))
        await fulfillment(of: [returned], timeout: 2)
        await Task.yield()
        XCTAssertEqual(committed, [14])
        queue.cancel()
    }
}
