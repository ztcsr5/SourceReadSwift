import Foundation

struct ReadingHistoryItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var author: String
    var coverURL: String?
    var sourceName: String
    var sourceURL: String
    var bookURL: String
    var intro: String?
    var currentChapterIndex: Int
    var currentChapterTitle: String?
    var currentParagraphIndex: Int?
    var totalChapters: Int
    var lastReadAt: Date
    var totalReadingSeconds: TimeInterval
    var readingSessionCount: Int

    var readingProgress: Double {
        guard totalChapters > 0 else { return 0 }
        return min(max(Double(currentChapterIndex + 1) / Double(totalChapters), 0), 1)
    }

    var asBookshelfBook: BookshelfBook {
        BookshelfBook(
            id: id,
            title: title,
            author: author,
            coverURL: coverURL,
            sourceName: sourceName,
            sourceURL: sourceURL,
            bookURL: bookURL,
            intro: intro,
            totalChapters: totalChapters,
            currentChapterIndex: currentChapterIndex,
            currentChapterTitle: currentChapterTitle,
            currentParagraphIndex: currentParagraphIndex,
            lastReadAt: lastReadAt,
            readingSessionCount: readingSessionCount,
            totalReadingSeconds: totalReadingSeconds
        )
    }

    var asSearchBook: SearchBook {
        SearchBook(
            name: title,
            author: author,
            coverUrl: coverURL,
            bookUrl: bookURL,
            sourceName: sourceName,
            sourceUrl: sourceURL,
            intro: intro
        )
    }
}

struct ReadingHistoryPersistence: Sendable {
    private let fileManager: FileManager
    private let fileName = "reading_history.json"
    private let rootURL: URL?

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL
    }

    func load() throws -> [ReadingHistoryItem] {
        let url = try storageURL()
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ReadingHistoryItem].self, from: data)
    }

    func save(_ items: [ReadingHistoryItem]) throws {
        let url = try storageURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(items)
        try data.write(to: url, options: [.atomic])
    }

    private func storageURL() throws -> URL {
        if let rootURL {
            return rootURL.appendingPathComponent(fileName)
        }
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("SourceReadSwift", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}

@MainActor
final class ReadingHistoryStore: ObservableObject {
    @Published private(set) var history: [ReadingHistoryItem] = []
    @Published private(set) var lastError: String?

    private let persistence: ReadingHistoryPersistence

    init(persistence: ReadingHistoryPersistence = ReadingHistoryPersistence()) {
        self.persistence = persistence
        do {
            history = try persistence.load().sorted { $0.lastReadAt > $1.lastReadAt }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func record(
        bookID: String,
        title: String,
        author: String,
        coverURL: String?,
        sourceName: String,
        sourceURL: String,
        bookURL: String,
        intro: String?,
        chapterIndex: Int,
        chapterTitle: String?,
        paragraphIndex: Int? = nil,
        totalChapters: Int = 0,
        sessionDuration: TimeInterval? = nil,
        incrementSession: Bool = false
    ) {
        let now = Date()
        if let idx = history.firstIndex(where: { $0.id == bookID }) {
            var item = history[idx]
            item.title = title
            item.author = author
            item.coverURL = coverURL ?? item.coverURL
            item.sourceName = sourceName
            item.sourceURL = sourceURL
            item.bookURL = bookURL
            item.intro = intro ?? item.intro
            item.currentChapterIndex = max(chapterIndex, 0)
            item.currentChapterTitle = chapterTitle ?? item.currentChapterTitle
            if let paragraphIndex {
                item.currentParagraphIndex = paragraphIndex
            }
            if totalChapters > 0 {
                item.totalChapters = max(totalChapters, item.totalChapters)
            }
            if let sessionDuration, sessionDuration > 0 {
                item.totalReadingSeconds += sessionDuration
            }
            if incrementSession {
                item.readingSessionCount += 1
            }
            item.lastReadAt = now
            history.remove(at: idx)
            history.insert(item, at: 0)
        } else {
            let newItem = ReadingHistoryItem(
                id: bookID,
                title: title,
                author: author,
                coverURL: coverURL,
                sourceName: sourceName,
                sourceURL: sourceURL,
                bookURL: bookURL,
                intro: intro,
                currentChapterIndex: max(chapterIndex, 0),
                currentChapterTitle: chapterTitle,
                currentParagraphIndex: paragraphIndex,
                totalChapters: totalChapters,
                lastReadAt: now,
                totalReadingSeconds: sessionDuration ?? 0,
                readingSessionCount: incrementSession ? 1 : 0
            )
            history.insert(newItem, at: 0)
        }
        if history.count > 500 {
            history.removeLast(history.count - 500)
        }
        persist()
    }

    func record(book: BookshelfBook, sessionDuration: TimeInterval? = nil, incrementSession: Bool = false) {
        record(
            bookID: book.id,
            title: book.title,
            author: book.author,
            coverURL: book.coverURL,
            sourceName: book.sourceName,
            sourceURL: book.sourceURL,
            bookURL: book.bookURL,
            intro: book.intro,
            chapterIndex: book.currentChapterIndex,
            chapterTitle: book.currentChapterTitle ?? book.latestChapterTitle,
            paragraphIndex: book.currentParagraphIndex,
            totalChapters: book.totalChapters,
            sessionDuration: sessionDuration,
            incrementSession: incrementSession
        )
    }

    func remove(id: String) {
        guard let idx = history.firstIndex(where: { $0.id == id }) else { return }
        history.remove(at: idx)
        persist()
    }

    func removeAll() {
        history.removeAll()
        persist()
    }

    private func persist() {
        do {
            try persistence.save(history)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
