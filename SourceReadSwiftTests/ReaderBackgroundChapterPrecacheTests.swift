import XCTest
@testable import SourceReadSwift

@MainActor
final class ReaderBackgroundChapterPrecacheTests: XCTestCase {
    private func chapter(_ index: Int) -> BookChapter {
        BookChapter(title: "第 \(index) 章", url: "https://fixture.invalid/\(index)",
                    bookUrl: "https://fixture.invalid/book", index: index)
    }

    func testRepeatedNearBoundarySignalsDoNotLaunchDuplicateLoads() async {
        let queue = ReaderBackgroundChapterPrecache()
        let started = expectation(description: "first request started")
        let saved = expectation(description: "first request committed")
        var release: CheckedContinuation<ChapterContent?, Never>?
        var requests = 0
        var commits = 0
        let target = chapter(4)
        let load: @MainActor (BookChapter) async -> ChapterContent? = { _ in
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
        release?.resume(returning: ChapterContent(chapter: target, title: target.title, paragraphs: ["正文"]))
        await fulfillment(of: [saved], timeout: 2)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(commits, 1)
        queue.cancel()
    }

    func testLeavingReaderRejectsAnUncooperativeLateLoadAndStopsRemainingChapters() async {
        let queue = ReaderBackgroundChapterPrecache()
        let started = expectation(description: "request started")
        let returned = expectation(description: "cancelled request returned")
        var release: CheckedContinuation<ChapterContent?, Never>?
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
        release?.resume(returning: ChapterContent(chapter: target, title: target.title, paragraphs: ["迟到正文"]))
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
        var release: CheckedContinuation<ChapterContent?, Never>?
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
            ChapterContent(chapter: chapter, title: chapter.title, paragraphs: ["新正文"])
        }, commit: { committed.append($0.chapter.index); saved.fulfill() })
        await fulfillment(of: [saved], timeout: 2)
        release?.resume(returning: ChapterContent(chapter: old, title: old.title, paragraphs: ["旧正文"]))
        await fulfillment(of: [returned], timeout: 2)
        await Task.yield()
        XCTAssertEqual(committed, [14])
        queue.cancel()
    }
}
