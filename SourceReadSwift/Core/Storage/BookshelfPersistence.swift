import Foundation

struct BookshelfPersistence: Sendable {
    // Full saves, progress sidecars and reloads share one FIFO across instances.
    // A pending progress write must never resurrect a sidecar after a deletion.
    private static let diskQueue = DispatchQueue(label: "SourceReadSwift.bookshelf.disk", qos: .utility)
    private let fileManager: FileManager
    private let fileName = "bookshelf_books.json"
    private let rootURL: URL?
    private let writeObserver: (@Sendable () -> Void)?

    init(fileManager: FileManager = .default, rootURL: URL? = nil, writeObserver: (@Sendable () -> Void)? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL
        self.writeObserver = writeObserver
    }

    func load() throws -> [BookshelfBook] {
        try Self.diskQueue.sync { try readSnapshot() }
    }

    private func readSnapshot() throws -> [BookshelfBook] {
        let url = try storageURL()
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var books = try decoder.decode([BookshelfBook].self, from: data)
        // A damaged progress sidecar must never hide an otherwise valid shelf.
        if let progressData = try? Data(contentsOf: progressURL()),
           let progress = try? JSONDecoder().decode([String: ReadingPosition].self, from: progressData) {
            for index in books.indices {
                guard let position = progress[books[index].id] else { continue }
                position.apply(to: &books[index])
            }
        }
        return books
    }

    func save(_ books: [BookshelfBook]) throws {
        try Self.diskQueue.sync { try writeSnapshot(books) }
    }

    /// Completes on the disk queue. UI callers must return to MainActor.
    func saveInBackground(_ books: [BookshelfBook], completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        Self.diskQueue.async { completion(Result { try writeSnapshot(books) }) }
    }

    private func writeSnapshot(_ books: [BookshelfBook]) throws {
        writeObserver?()
        let span = PerformanceSignpost.begin("bookshelf.snapshot.write")
        defer { PerformanceSignpost.end("bookshelf.snapshot.write", id: span) }
        let url = try storageURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(books)
        try AppStorageDirectory.safeWrite(data, to: url, fileManager: fileManager)
        // The full snapshot contains the latest in-memory progress. Removing
        // its sidecar also prevents deleted books/source resets being revived.
        let progress = try progressURL()
        if fileManager.fileExists(atPath: progress.path) { try fileManager.removeItem(at: progress) }
    }

    /// Page/TOC changes used to JSON-encode *every local book's entire text*
    /// synchronously. Persist only these small fields on the interactive path.
    /// Full saves, backup/restore and the canonical shelf format stay unchanged.
    func saveReadingProgress(_ books: [BookshelfBook]) throws {
        try Self.diskQueue.sync { try writeReadingProgress(books) }
    }

    /// Enqueues an immutable snapshot; encoding and filesystem work run off main.
    func saveReadingProgressInBackground(_ books: [BookshelfBook], completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        Self.diskQueue.async { completion(Result { try writeReadingProgress(books) }) }
    }

    /// An asynchronous durability boundary, including writes from other instances.
    func waitForPendingWrites() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Self.diskQueue.async { continuation.resume() }
        }
    }

    private func writeReadingProgress(_ books: [BookshelfBook]) throws {
        writeObserver?()
        let span = PerformanceSignpost.begin("bookshelf.progress.write")
        defer { PerformanceSignpost.end("bookshelf.progress.write", id: span) }
        let positions = Dictionary(uniqueKeysWithValues: books.map { ($0.id, ReadingPosition($0)) })
        let data = try JSONEncoder().encode(positions)
        try AppStorageDirectory.safeWrite(data, to: progressURL(), fileManager: fileManager)
    }

    private func progressURL() throws -> URL {
        // Same container as the canonical shelf, including injected test roots.
        try storageURL().deletingLastPathComponent()
            .appendingPathComponent("bookshelf_reading_positions.json")
    }

    private struct ReadingPosition: Codable {
        let chapter: Int
        let title: String?
        let paragraph: Int?
        let comicPosition: ComicReadingPosition?
        let total: Int
        let seen: Int?
        let lastReadAt: Date?
        let lastOpenedAt: Date?

        init(_ book: BookshelfBook) {
            chapter = book.currentChapterIndex; title = book.currentChapterTitle
            paragraph = book.currentParagraphIndex; total = book.totalChapters
            comicPosition = book.comicPosition
            seen = book.seenTotalChapters; lastReadAt = book.lastReadAt
            lastOpenedAt = book.lastOpenedAt
        }

        func apply(to book: inout BookshelfBook) {
            // A newer canonical snapshot wins if a crash occurred between its
            // atomic write and clearing the old journal (ISO dates round to s).
            guard let lastReadAt,
                  lastReadAt.timeIntervalSince1970.rounded(.down) >= (book.lastReadAt ?? .distantPast).timeIntervalSince1970 else { return }
            book.currentChapterIndex = chapter; book.currentChapterTitle = title
            book.currentParagraphIndex = paragraph; book.totalChapters = max(book.totalChapters, total)
            book.comicPosition = comicPosition
            book.seenTotalChapters = seen; book.lastReadAt = lastReadAt
            book.lastOpenedAt = lastOpenedAt
        }
    }

    private func storageURL() throws -> URL {
        AppStorageDirectory.appStorageURL(fileName: fileName, fileManager: fileManager, rootURL: rootURL)
    }
}
