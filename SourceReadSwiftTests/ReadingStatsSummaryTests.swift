import XCTest
@testable import SourceReadSwift

final class ReadingStatsSummaryTests: XCTestCase {
    func testLegacyLifetimeTotalIsNotInventedAsTodaysReading() {
        let now = Date()
        var book = BookshelfBook(searchBook: SearchBook(name: "Legacy", author: nil, coverUrl: nil,
            bookUrl: "https://fixture.invalid/book", sourceName: "Fixture", sourceUrl: "https://fixture.invalid"))
        book.totalReadingSeconds = 100_000
        book.lastReadAt = now
        let summary = ReadingStatsSummary(books: [book], referenceDate: now)
        XCTAssertEqual(summary.totalReadingSeconds, 100_000, "Keep old lifetime totals")
        XCTAssertEqual(summary.todayReadingSeconds, 0, "The last opened date cannot date every historical session")
        XCTAssertTrue(summary.weeklyDistribution.allSatisfy { $0.seconds == 0 })
    }
    func testAggregatesReadingStatsFromBookshelfBooks() {
        let now = Date(timeIntervalSince1970: 1_792_008_000)
        let zone = TimeZone(secondsFromGMT: 0)!
        let day = ReadingDayActivity.key(for: now, calendar: ReadingDayActivity.calendar(in: zone))
        let remote = BookshelfBook(
            id: "remote",
            title: "Remote Book",
            author: "A",
            coverURL: nil,
            sourceName: "Remote",
            sourceURL: "https://example.com",
            bookURL: "https://example.com/book",
            intro: nil,
            totalChapters: 10,
            currentChapterIndex: 4,
            bookmarks: [
                ReaderBookmark(chapterIndex: 1, chapterTitle: "One", snippet: "A"),
                ReaderBookmark(chapterIndex: 2, chapterTitle: "Two", snippet: "B")
            ],
            lastReadAt: now,
            readingSessionCount: 2,
            totalReadingSeconds: 600,
            readingSecondsByDay: [day: 600]
        )
        let local = BookshelfBook(
            id: "local",
            title: "Local Book",
            author: "B",
            coverURL: nil,
            sourceName: "Local",
            sourceURL: "local://text",
            bookURL: "local",
            intro: nil,
            totalChapters: 4,
            currentChapterIndex: 1,
            bookmarks: [],
            lastReadAt: now.addingTimeInterval(-100),
            readingSessionCount: 1,
            totalReadingSeconds: 120,
            readingSecondsByDay: [day: 120]
        )

        let summary = ReadingStatsSummary(books: [remote, local], referenceDate: now, timeZone: zone)

        XCTAssertEqual(summary.totalBooks, 2)
        XCTAssertEqual(summary.localBooks, 1)
        XCTAssertEqual(summary.remoteBooks, 1)
        XCTAssertEqual(summary.readBooks, 2)
        XCTAssertEqual(summary.bookmarkedBooks, 1)
        XCTAssertEqual(summary.totalBookmarks, 2)
        XCTAssertEqual(summary.totalSessions, 3)
        XCTAssertEqual(summary.totalReadingSeconds, 720)
        XCTAssertEqual(summary.averageProgress, 0.5, accuracy: 0.001)
        XCTAssertEqual(summary.mostReadBook?.id, "remote")
        XCTAssertEqual(summary.recentBooks.map(\.id), ["remote", "local"])
        XCTAssertEqual(summary.estimatedWordsRead, Int((720.0 / 60.0) * 380.0))
        XCTAssertEqual(summary.weeklyDistribution.count, 7)
        XCTAssertGreaterThanOrEqual(summary.streakDays, 1)
        XCTAssertEqual(summary.todayReadingSeconds, 720)
    }

    func testForegroundPausesExcludeBackgroundAndSplitAtLocalMidnight() throws {
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3_600))
        let calendar = ReadingDayActivity.calendar(in: zone)
        let midnight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 6)))
        var session = ForegroundReadingSession()
        session.resume(at: midnight.addingTimeInterval(-20))
        session.resume(at: midnight.addingTimeInterval(-10))
        XCTAssertEqual(session.todaySeconds(at: midnight.addingTimeInterval(10), calendar: calendar), 10)
        let first = try XCTUnwrap(session.pause(at: midnight.addingTimeInterval(10), calendar: calendar))
        XCTAssertEqual(first.days, [20261105: 20, 20261106: 10])
        XCTAssertTrue(first.startsSession)
        XCTAssertNil(session.pause(at: midnight.addingTimeInterval(600), calendar: calendar))
        XCTAssertEqual(session.todaySeconds(at: midnight.addingTimeInterval(600), calendar: calendar), 0)

        session.resume(at: midnight.addingTimeInterval(600))
        let second = try XCTUnwrap(session.pause(at: midnight.addingTimeInterval(630), calendar: calendar))
        XCTAssertEqual(second.days, [20261106: 30])
        XCTAssertFalse(second.startsSession)
    }

    @MainActor func testForegroundDaysPersistAndStreakSpansTheSameBook() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = BookshelfPersistence(rootURL: root)
        let store = BookshelfStore(persistence: persistence)
        store.addLocalTextBook(LocalTextBook(title: "Book", author: "Author", chapters: [
            LocalTextChapter(title: "Chapter", paragraphs: ["Text"], index: 0)
        ]))
        let id = try XCTUnwrap(store.books.first?.id)
        store.recordReadingSession(bookID: id, duration: 3_600)
        store.recordReadingActivity(bookID: id, days: [20261104: 20, 20261105: 30], startsSession: true)
        store.recordReadingActivity(bookID: id, days: [20261105: 10], startsSession: false)
        await store.waitForPendingWrites()
        let books = try persistence.load()
        XCTAssertEqual(books.first?.readingSessionCount, 2)
        XCTAssertEqual(books.first?.readingSecondsByDay, [20261104: 20, 20261105: 40])
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let calendar = ReadingDayActivity.calendar(in: zone)
        let friday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 6)))
        let stats = ReadingStatsSummary(books: books, referenceDate: friday, timeZone: zone)
        XCTAssertEqual(stats.totalReadingSeconds, 3_660)
        XCTAssertEqual(stats.todayReadingSeconds, 0)
        XCTAssertEqual(stats.weeklyDistribution.suffix(3).map(\.seconds), [20, 40, 0])
        XCTAssertEqual(stats.streakDays, 2)
    }

    func testEmptyStatsAreZero() {
        let summary = ReadingStatsSummary(books: [])

        XCTAssertEqual(summary.totalBooks, 0)
        XCTAssertEqual(summary.averageProgress, 0)
        XCTAssertNil(summary.mostReadBook)
        XCTAssertTrue(summary.recentBooks.isEmpty)
        XCTAssertEqual(summary.estimatedWordsRead, 0)
        XCTAssertEqual(summary.streakDays, 0)
        XCTAssertEqual(summary.todayReadingSeconds, 0)
        XCTAssertEqual(summary.weeklyDistribution.count, 7)
    }
}
