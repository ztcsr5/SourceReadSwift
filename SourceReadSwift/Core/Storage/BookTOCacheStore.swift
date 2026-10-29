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
    }

    private let fileManager: FileManager
    private let rootURL: URL?
    private var memory: [String: BookTOCacheEntry] = [:]
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
        guard let decoded = loadFromDisk(key: key),
              decoded.entry.version == BookTOCacheEntry.schemaVersion,
              !decoded.entry.chapters.isEmpty else { return nil }
        memory[key] = decoded.entry
        touch(key)
        trimMemory()
        return decoded.entry
    }

    func chapters(sourceURL: String, bookURL: String) -> [BookChapter] {
        entry(sourceURL: sourceURL, bookURL: bookURL)?.chapters ?? []
    }

    func save(
        detail: BookDetail?,
        chapters: [BookChapter],
        sourceURL: String,
        bookURL: String,
        at date: Date = Date()
    ) {
        guard !chapters.isEmpty else { return }
        let key = cacheKey(sourceURL: sourceURL, bookURL: bookURL)
        let entry = BookTOCacheEntry(
            version: BookTOCacheEntry.schemaVersion,
            sourceURL: sourceURL,
            bookURL: bookURL,
            detail: detail,
            chapters: chapters,
            updatedAt: date
        )
        memory[key] = entry
        touch(key)
        trimMemory()
        writeToDisk(entry, key: key)
    }

    func invalidate(sourceURL: String, bookURL: String) {
        let key = cacheKey(sourceURL: sourceURL, bookURL: bookURL)
        memory.removeValue(forKey: key)
        memoryOrder.removeAll { $0 == key }
        guard let url = try? storageURL(key: key) else { return }
        try? fileManager.removeItem(at: url)
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

    private func storageURL(key: String) throws -> URL {
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

    private func loadFromDisk(key: String) -> (entry: BookTOCacheEntry, url: URL)? {
        guard let url = try? storageURL(key: key),
              fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let persisted = try? decoder.decode(Persisted.self, from: data) else { return nil }
        let entry = BookTOCacheEntry(
            version: persisted.version,
            sourceURL: persisted.sourceURL,
            bookURL: persisted.bookURL,
            detail: persisted.detail,
            chapters: persisted.chapters,
            updatedAt: persisted.updatedAt
        )
        return (entry, url)
    }

    private func writeToDisk(_ entry: BookTOCacheEntry, key: String) {
        guard let url = try? storageURL(key: key) else { return }
        let persisted = Persisted(
            version: entry.version,
            sourceURL: entry.sourceURL,
            bookURL: entry.bookURL,
            detail: entry.detail,
            chapters: entry.chapters,
            updatedAt: entry.updatedAt
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(persisted) else { return }
        let fileManager = self.fileManager
        DispatchQueue.global(qos: .utility).async {
            try? AppStorageDirectory.safeWrite(data, to: url, fileManager: fileManager)
        }
    }
}
