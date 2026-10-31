import Foundation

struct BookshelfPersistence {
    private let fileManager: FileManager
    private let fileName = "bookshelf_books.json"
    private let rootURL: URL?

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL
    }

    func load() throws -> [BookshelfBook] {
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
        let total: Int
        let seen: Int?
        let lastReadAt: Date?

        init(_ book: BookshelfBook) {
            chapter = book.currentChapterIndex; title = book.currentChapterTitle
            paragraph = book.currentParagraphIndex; total = book.totalChapters
            seen = book.seenTotalChapters; lastReadAt = book.lastReadAt
        }

        func apply(to book: inout BookshelfBook) {
            // A newer canonical snapshot wins if a crash occurred between its
            // atomic write and clearing the old journal (ISO dates round to s).
            guard let lastReadAt,
                  lastReadAt.timeIntervalSince1970.rounded(.down) >= (book.lastReadAt ?? .distantPast).timeIntervalSince1970 else { return }
            book.currentChapterIndex = chapter; book.currentChapterTitle = title
            book.currentParagraphIndex = paragraph; book.totalChapters = max(book.totalChapters, total)
            book.seenTotalChapters = seen; book.lastReadAt = lastReadAt
        }
    }

    private func storageURL() throws -> URL {
        AppStorageDirectory.appStorageURL(fileName: fileName, fileManager: fileManager, rootURL: rootURL)
    }
}
