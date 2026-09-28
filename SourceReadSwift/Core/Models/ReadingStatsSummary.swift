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

    init(books: [BookshelfBook], referenceDate: Date = Date()) {
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

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)

        todayReadingSeconds = books.reduce(0.0) { sum, book in
            guard let lastRead = book.lastReadAt, calendar.isDate(lastRead, inSameDayAs: referenceDate) else {
                return sum
            }
            return sum + (book.totalReadingSeconds ?? 0)
        }

        let weekdaySymbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        var days: [DayReadingStat] = []
        for offset in (0..<7).reversed() {
            guard let dayDate = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let isCurrentDay = (offset == 0)
            let weekday = calendar.component(.weekday, from: dayDate) - 1
            let label = isCurrentDay ? "今天" : weekdaySymbols[max(0, min(weekday, 6))]

            let daySeconds = books.reduce(0.0) { sum, book in
                guard let lastRead = book.lastReadAt, calendar.isDate(lastRead, inSameDayAs: dayDate) else {
                    return sum
                }
                return sum + (book.totalReadingSeconds ?? 0)
            }
            days.append(DayReadingStat(dayLabel: label, date: dayDate, seconds: daySeconds, isToday: isCurrentDay))
        }
        weeklyDistribution = days

        // Calculate consecutive streak
        var streak = 0
        var checkDate = today
        while true {
            let hasReadOnDate = books.contains { book in
                guard let lastRead = book.lastReadAt else { return false }
                return calendar.isDate(lastRead, inSameDayAs: checkDate)
            }
            if hasReadOnDate {
                streak += 1
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = previousDay
            } else if streak == 0, let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
                // If user hasn't read today yet, check yesterday to continue yesterday's streak
                let hasReadYesterday = books.contains { book in
                    guard let lastRead = book.lastReadAt else { return false }
                    return calendar.isDate(lastRead, inSameDayAs: yesterday)
                }
                if hasReadYesterday {
                    streak += 1
                    guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: yesterday) else { break }
                    checkDate = dayBefore
                } else {
                    break
                }
            } else {
                break
            }
        }
        streakDays = streak
    }
}
