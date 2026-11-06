import Foundation

struct DayReadingStat: Identifiable, Equatable, Sendable {
    var id: String { dayLabel }
    let dayLabel: String
    let date: Date
    let seconds: TimeInterval
    let isToday: Bool

    init(dayLabel: String, date: Date, seconds: TimeInterval, isToday: Bool) {
        self.dayLabel = dayLabel
        self.date = date
        self.seconds = seconds
        self.isToday = isToday
    }
}

/// Local civil dates are stored as Gregorian YYYYMMDD keys, so travelling does not
/// reassign previously recorded activity to a different day.
enum ReadingDayActivity {
    static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func key(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return (components.year ?? 0) * 10_000 + (components.month ?? 0) * 100 + (components.day ?? 0)
    }

    static func split(from start: Date, to end: Date, calendar: Calendar) -> [Int: TimeInterval] {
        var result: [Int: TimeInterval] = [:]
        var cursor = start
        while cursor < end, let day = calendar.dateInterval(of: .day, for: cursor), day.end > cursor {
            let boundary = min(day.end, end)
            result[key(for: cursor, calendar: calendar), default: 0] += boundary.timeIntervalSince(cursor)
            cursor = boundary
        }
        return result
    }
}

/// Tracks only the foreground intervals of one reader presentation.
struct ForegroundReadingSession {
    private var startedAt: Date?
    private var hasRecordedSession = false

    mutating func resume(at date: Date) {
        if startedAt == nil { startedAt = date }
    }

    mutating func pause(at date: Date, calendar: Calendar) -> (days: [Int: TimeInterval], startsSession: Bool)? {
        guard let start = startedAt else { return nil }
        startedAt = nil
        guard date.timeIntervalSince(start) > 1 else { return nil }
        let days = ReadingDayActivity.split(from: start, to: date, calendar: calendar)
        guard !days.isEmpty else { return nil }
        let startsSession = !hasRecordedSession
        hasRecordedSession = true
        return (days, startsSession)
    }

    func todaySeconds(at date: Date, calendar: Calendar) -> TimeInterval {
        guard let start = startedAt, let day = calendar.dateInterval(of: .day, for: date) else { return 0 }
        return max(0, date.timeIntervalSince(max(day.start, start)))
    }
}

struct ReadingStatsSummary: Equatable, Sendable {
    let totalBooks: Int
    let localBooks: Int
    let remoteBooks: Int
    let readBooks: Int
    let bookmarkedBooks: Int
    let totalBookmarks: Int
    let totalSessions: Int
    let totalReadingSeconds: TimeInterval
    let averageProgress: Double
    let mostReadBook: BookshelfBook?
    let recentBooks: [BookshelfBook]
    let estimatedWordsRead: Int
    let todayReadingSeconds: TimeInterval
    let streakDays: Int
    let weeklyDistribution: [DayReadingStat]

    init(books: [BookshelfBook], referenceDate: Date = Date(), timeZone: TimeZone = .current) {
        totalBooks = books.count
        localBooks = books.filter { $0.sourceURL.hasPrefix("local://") }.count
        remoteBooks = totalBooks - localBooks
        readBooks = books.filter { $0.lastReadAt != nil }.count
        bookmarkedBooks = books.filter { !($0.bookmarks ?? []).isEmpty }.count
        totalBookmarks = books.reduce(0) { $0 + ($1.bookmarks?.count ?? 0) }
        totalSessions = books.reduce(0) { $0 + ($1.readingSessionCount ?? 0) }
        totalReadingSeconds = books.reduce(0) { $0 + ($1.totalReadingSeconds ?? 0) }
        averageProgress = books.isEmpty
            ? 0
            : books.reduce(0) { $0 + $1.readingProgress } / Double(books.count)
        mostReadBook = books
            .filter { ($0.totalReadingSeconds ?? 0) > 0 }
            .max { ($0.totalReadingSeconds ?? 0) < ($1.totalReadingSeconds ?? 0) }
        recentBooks = Array(
            books
                .filter { $0.lastReadAt != nil }
                .sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
                .prefix(5)
        )
        // Average Chinese reading speed is roughly 380 - 450 words per minute.
        estimatedWordsRead = Int((totalReadingSeconds / 60.0) * 380.0)

        let calendar = ReadingDayActivity.calendar(in: timeZone)
        let today = calendar.startOfDay(for: referenceDate)
        var secondsByDay: [Int: TimeInterval] = [:]
        for book in books {
            for (key, seconds) in book.readingSecondsByDay ?? [:] where seconds.isFinite && seconds > 0 {
                secondsByDay[key, default: 0] += seconds
            }
        }
        func seconds(on date: Date) -> TimeInterval {
            secondsByDay[ReadingDayActivity.key(for: date, calendar: calendar), default: 0]
        }
        todayReadingSeconds = seconds(on: today)

        let weekdaySymbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        weeklyDistribution = (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let weekday = calendar.component(.weekday, from: date) - 1
            return DayReadingStat(dayLabel: offset == 0 ? "今天" : weekdaySymbols[weekday],
                                  date: date, seconds: seconds(on: date), isToday: offset == 0)
        }

        // Yesterday's run remains active until today ends, but opening a book
        // without recording foreground time cannot create a day in the streak.
        var streak = 0
        var date = todayReadingSeconds > 0 ? today : calendar.date(byAdding: .day, value: -1, to: today) ?? today
        while seconds(on: date) > 0 {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date), previous < date else { break }
            date = previous
        }
        streakDays = streak
    }
}
