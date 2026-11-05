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
    var mediaKind: BookSourceKind? = nil

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
            totalReadingSeconds: totalReadingSeconds,
            mediaKind: mediaKind
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
            intro: intro,
            mediaKind: mediaKind
        )
    }
}

struct ReadingHistoryPersistence: Sendable {
    private static let diskQueue = DispatchQueue(label: "SourceReadSwift.reading-history.disk", qos: .utility)
    private let fileManager: FileManager
    private let fileName = "reading_history.json"
    private let rootURL: URL?
    private let writeObserver: (@Sendable () -> Void)?

    init(fileManager: FileManager = .default, rootURL: URL? = nil, writeObserver: (@Sendable () -> Void)? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL
        self.writeObserver = writeObserver
    }

    func load() throws -> [ReadingHistoryItem] {
        try Self.diskQueue.sync { try readSnapshot() }
    }

    private func readSnapshot() throws -> [ReadingHistoryItem] {
        let url = try storageURL()
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ReadingHistoryItem].self, from: data)
    }

    func save(_ items: [ReadingHistoryItem]) throws {
        try Self.diskQueue.sync { try writeSnapshot(items) }
    }

    /// Completion runs on the ordered writer queue, not MainActor.
    func saveInBackground(_ items: [ReadingHistoryItem], completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        Self.diskQueue.async { completion(Result { try writeSnapshot(items) }) }
    }

    func waitForPendingWrites() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Self.diskQueue.async { continuation.resume() }
        }
    }

    private func writeSnapshot(_ items: [ReadingHistoryItem]) throws {
        writeObserver?()
        let span = PerformanceSignpost.begin("reading-history.write")
        defer { PerformanceSignpost.end("reading-history.write", id: span) }
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
    private var persistenceRevision = 0

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
        incrementSession: Bool = false,
        mediaKind: BookSourceKind? = nil
    ) {
        let now = Date()
        var nextHistory = history
        if let idx = nextHistory.firstIndex(where: { $0.id == bookID }) {
            var item = nextHistory[idx]
            item.title = title
            item.author = author
            item.coverURL = coverURL ?? item.coverURL
            item.sourceName = sourceName
            item.sourceURL = sourceURL
            item.bookURL = bookURL
            item.intro = intro ?? item.intro
            item.mediaKind = mediaKind ?? item.mediaKind
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
            nextHistory.remove(at: idx)
            nextHistory.insert(item, at: 0)
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
                readingSessionCount: incrementSession ? 1 : 0,
                mediaKind: mediaKind
            )
            nextHistory.insert(newItem, at: 0)
        }
        if nextHistory.count > 500 {
            nextHistory.removeLast(nextHistory.count - 500)
        }
        history = nextHistory
        persist(inBackground: true)
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
            incrementSession: incrementSession,
            mediaKind: book.mediaKind
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

    /// Waits without running encoding or disk IO on MainActor.
    func waitForPendingWrites() async { await persistence.waitForPendingWrites() }

    private func persist(inBackground: Bool = false) {
        persistenceRevision &+= 1
        let revision = persistenceRevision
        if inBackground {
            persistence.saveInBackground(history) { [weak self] result in
                Task { @MainActor [weak self] in self?.completePersistence(result, revision: revision) }
            }
            return
        }
        do {
            try persistence.save(history)
            if lastError != nil { lastError = nil }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func completePersistence(_ result: Result<Void, Error>, revision: Int) {
        guard revision == persistenceRevision else {
            if case .failure = result { PerformanceSignpost.event("reading-history.write", "Superseded background write failed") }
            return
        }
        let message: String?
        switch result {
        case .success: message = nil
        case .failure(let error): message = "保存阅读历史失败：\(error.localizedDescription)"
        }
        if lastError != message { lastError = message }
    }
}
