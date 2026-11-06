import Foundation

/// One persisted table of contents (plus the book-detail record that produced
/// it). The reader used to block on `getBookDetail` and then on a serial,
/// page-by-page `getChapterList`; a 30-page TOC therefore took tens of seconds
/// and the detail sheet showed nothing. Persisting the last successful TOC per
/// book lets both entry points paint the chapter list immediately and refresh
/// in the background.
struct BookTOCacheEntry: Codable, Sendable {
    static let schemaVersion = 1

    let version: Int
    let sourceURL: String
    let bookURL: String
    let detail: BookDetail?
    let chapters: [BookChapter]
    let updatedAt: Date
    var isComplete: Bool? = nil
}

/// Per-book JSON files under the app storage folder.
///
/// A single aggregate file made launch slow once a few hundred books were
/// opened (tens of MB decoded before the first frame), so each book owns a
/// small file named after a stable FNV-1a hash of `sourceURL|bookURL`.
@MainActor
final class BookTOCacheStore {
    private struct Persisted: Codable {
        let version: Int
        let sourceURL: String
        let bookURL: String
        let detail: BookDetail?
        let chapters: [BookChapter]
        let updatedAt: Date
        var isComplete: Bool? = nil
    }

    private static let writer = DispatchQueue(label: "BookTOCache.writer", qos: .utility)
    private let fileManager: FileManager
    private let rootURL: URL?
    private var memory: [String: BookTOCacheEntry] = [:]
    private struct ColdRead {
        let id: UUID
        let task: Task<BookTOCacheEntry?, Never>
    }
    private var coldReads: [String: ColdRead] = [:]
    private var memoryOrder: [String] = []
    private let memoryLimit = 6

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL
    }

    func entry(sourceURL: String, bookURL: String) -> BookTOCacheEntry? {
        let key = cacheKey(sourceURL: sourceURL, bookURL: bookURL)
        if let cached = memory[key] {
            touch(key)
            return cached
        }
        let url = storageURL(key: key)
        guard let bytes = Self.writer.sync(execute: { try? Data(contentsOf: url) }),
              let entry = Self.decodeEntry(bytes) else { return nil }
        memory[key] = entry
        touch(key)
        trimMemory()
        return entry
    }

    /// Keeps a memory hit immediate, but does not block the reader transition on the disk queue.
    func entryForReader(sourceURL: String, bookURL: String) async -> BookTOCacheEntry? {
        guard !Task.isCancelled else { return nil }
        let key = cacheKey(sourceURL: sourceURL, bookURL: bookURL)
        if let cached = memory[key] {
            touch(key)
            return cached
        }
        let read = coldReads[key] ?? beginColdRead(key: key)
        let entry = await read.task.value
        if coldReads[key]?.id == read.id {
            coldReads.removeValue(forKey: key)
            if let entry, entry.sourceURL == sourceURL, entry.bookURL == bookURL {
                memory[key] = entry
                touch(key)
                trimMemory()
            }
        }
        return Task.isCancelled ? nil : memory[key]
    }

    private func beginColdRead(key: String) -> ColdRead {
        let manager = fileManager, root = rootURL
        let task = Task<BookTOCacheEntry?, Never> {
            await withCheckedContinuation { continuation in
                Self.writer.async {
                    let url = Self.storageURL(key: key, fileManager: manager, rootURL: root)
                    let bytes = try? Data(contentsOf: url)
                    continuation.resume(returning: bytes.flatMap { Self.decodeEntry($0) })
                }
            }
        }
        let read = ColdRead(id: UUID(), task: task)
        coldReads[key] = read
        return read
    }

    func chapters(sourceURL: String, bookURL: String) -> [BookChapter] {
        entry(sourceURL: sourceURL, bookURL: bookURL)?.chapters ?? []
    }

    func save(
        detail: BookDetail?,
        chapters: [BookChapter],
        sourceURL: String,
        bookURL: String,
        isComplete: Bool = true,
        at date: Date = Date()
    ) {
        guard !chapters.isEmpty else { return }
        let key = cacheKey(sourceURL: sourceURL, bookURL: bookURL)
        if !isComplete, let existing = self.entry(sourceURL: sourceURL, bookURL: bookURL),
           existing.isComplete == true { return }
        var entry = BookTOCacheEntry(
            version: BookTOCacheEntry.schemaVersion,
            sourceURL: sourceURL,
            bookURL: bookURL,
            detail: detail,
            chapters: chapters,
            updatedAt: date
        )
        entry.isComplete = isComplete
        coldReads.removeValue(forKey: key)
        memory[key] = entry
        touch(key)
        trimMemory()
        writeToDisk(entry, key: key)
    }

    func invalidate(sourceURL: String, bookURL: String) {
        let key = cacheKey(sourceURL: sourceURL, bookURL: bookURL)
        coldReads.removeValue(forKey: key)
        memory.removeValue(forKey: key)
        memoryOrder.removeAll { $0 == key }
        let url = storageURL(key: key)
        let manager = fileManager
        Self.writer.async { try? manager.removeItem(at: url) }
    }

    // MARK: - Key / memory

    private func cacheKey(sourceURL: String, bookURL: String) -> String {
        "\(sourceURL)|\(bookURL)"
    }

    private func touch(_ key: String) {
        memoryOrder.removeAll { $0 == key }
        memoryOrder.append(key)
    }

    private func trimMemory() {
        while memoryOrder.count > memoryLimit {
            let evicted = memoryOrder.removeFirst()
            memory.removeValue(forKey: evicted)
        }
    }

    // MARK: - Disk

    private func storageURL(key: String) -> URL {
        Self.storageURL(key: key, fileManager: fileManager, rootURL: rootURL)
    }

    nonisolated private static func storageURL(key: String, fileManager: FileManager, rootURL: URL?) -> URL {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let name = "book-toc-\(String(hash, radix: 16)).json"
        return AppStorageDirectory.appStorageURL(
            fileName: name,
            fileManager: fileManager,
            rootURL: rootURL
        )
    }

    nonisolated private static func decodeEntry(_ bytes: Data) -> BookTOCacheEntry? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let persisted = try? decoder.decode(Persisted.self, from: bytes),
              persisted.version == BookTOCacheEntry.schemaVersion, !persisted.chapters.isEmpty else { return nil }
        var entry = BookTOCacheEntry(
            version: persisted.version,
            sourceURL: persisted.sourceURL,
            bookURL: persisted.bookURL,
            detail: persisted.detail,
            chapters: persisted.chapters,
            updatedAt: persisted.updatedAt
        )
        entry.isComplete = persisted.isComplete
        return entry
    }

    private func writeToDisk(_ entry: BookTOCacheEntry, key: String) {
        let url = storageURL(key: key)
        var persisted = Persisted(
            version: entry.version,
            sourceURL: entry.sourceURL,
            bookURL: entry.bookURL,
            detail: entry.detail,
            chapters: entry.chapters,
            updatedAt: entry.updatedAt
        )
        persisted.isComplete = entry.isComplete
        let fileManager = self.fileManager
        Self.writer.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(persisted) else { return }
            try? AppStorageDirectory.safeWrite(data, to: url, fileManager: fileManager)
        }
    }
}
