import Foundation

struct ChapterContentCacheEntry: Identifiable, Codable, Hashable, Sendable {
    var id: String { key }
    let key: String
    let sourceURL: String
    let chapterURL: String
    let bookURL: String
    let chapterIndex: Int?
    let title: String
    let paragraphs: [String]
    let nextContentUrl: String?
    let imageStyle: String?
    /// Legado `payAction` is stored with the chapter so a cached chapter can
    /// still offer “购买本章” after an offline relaunch.
    let payAction: String?
    let purifySignature: String
    let cachedAt: Date

    /// Keep the memberwise construction stable across Swift toolchains.  A
    /// defaulted stored property is not consistently exposed by synthesized
    /// initializers when the project is generated on a different Xcode
    /// version, which previously broke the device/IPA workflow at this call
    /// site.  The explicit initializer also preserves backwards-compatible
    /// decoding of cache files that predate `chapterIndex`.
    init(
        key: String,
        sourceURL: String,
        chapterURL: String,
        bookURL: String,
        chapterIndex: Int? = nil,
        title: String,
        paragraphs: [String],
        nextContentUrl: String?,
        imageStyle: String? = nil,
        payAction: String? = nil,
        purifySignature: String,
        cachedAt: Date
    ) {
        self.key = key
        self.sourceURL = sourceURL
        self.chapterURL = chapterURL
        self.bookURL = bookURL
        self.chapterIndex = chapterIndex
        self.title = title
        self.paragraphs = paragraphs
        self.nextContentUrl = nextContentUrl
        self.imageStyle = imageStyle
        self.payAction = payAction
        self.purifySignature = purifySignature
        self.cachedAt = cachedAt
    }

    var estimatedByteCount: Int {
        title.utf8.count
            + chapterURL.utf8.count
            + bookURL.utf8.count
            + paragraphs.reduce(0) { $0 + $1.utf8.count }
    }
}

@MainActor
final class ChapterContentCacheStore: ObservableObject {
    @Published private(set) var entries: [ChapterContentCacheEntry] = []
    @Published private(set) var lastError: String?

    private let persistence: ChapterContentCachePersistence
    private let maxEntryCount: Int
    private var persistenceRevision = 0

    var estimatedByteCount: Int {
        entries.reduce(0) { $0 + $1.estimatedByteCount }
    }

    init(
        persistence: ChapterContentCachePersistence = ChapterContentCachePersistence(),
        maxEntryCount: Int = 500
    ) {
        self.persistence = persistence
        self.maxEntryCount = maxEntryCount
        do {
            entries = Array(try persistence.load().prefix(maxEntryCount))
        } catch {
            lastError = error.localizedDescription
        }
    }

    func content(sourceURL: String, chapter: BookChapter, purifyRules: [String]) -> ChapterContent? {
        let key = cacheKey(sourceURL: sourceURL, chapterURL: chapter.url)
        let signature = purifySignature(purifyRules)
        guard let entry = entries.first(where: { $0.key == key && $0.purifySignature == signature }) else {
            return nil
        }
        return ChapterContent(
            chapter: chapter,
            title: entry.title,
            paragraphs: entry.paragraphs,
            nextContentUrl: entry.nextContentUrl,
            imageStyle: entry.imageStyle,
            payAction: entry.payAction
        )
    }

    func staleContent(sourceURL: String, chapter: BookChapter) -> ChapterContent? {
        let key = cacheKey(sourceURL: sourceURL, chapterURL: chapter.url)
        guard let entry = entries.first(where: { $0.key == key }) else {
            return nil
        }
        return ChapterContent(
            chapter: chapter,
            title: entry.title,
            paragraphs: entry.paragraphs,
            nextContentUrl: entry.nextContentUrl,
            imageStyle: entry.imageStyle,
            payAction: entry.payAction
        )
    }

    func isCached(sourceURL: String, chapter: BookChapter, purifyRules: [String]) -> Bool {
        content(sourceURL: sourceURL, chapter: chapter, purifyRules: purifyRules) != nil
    }

    /// Refresh the LRU position when a chapter is actually read.
    ///
    /// `save` only marks a chapter as cached when it first arrives. Without a
    /// touch, a chapter read for an hour could still be evicted by 500 newer
    /// prefetches, and walking back would show a loading page even though the
    /// user had just read it. One write per chapter transition is cheap.
    func markRead(
        sourceURL: String,
        chapter: BookChapter,
        purifyRules: [String],
        at date: Date = Date()
    ) {
        let key = cacheKey(sourceURL: sourceURL, chapterURL: chapter.url)
        let signature = purifySignature(purifyRules)
        guard let index = entries.firstIndex(where: { $0.key == key && $0.purifySignature == signature }) else {
            return
        }
        let entry = entries.remove(at: index)
        entries.insert(
            ChapterContentCacheEntry(
                key: entry.key,
                sourceURL: entry.sourceURL,
                chapterURL: entry.chapterURL,
                bookURL: entry.bookURL,
                chapterIndex: entry.chapterIndex,
                title: entry.title,
                paragraphs: entry.paragraphs,
                nextContentUrl: entry.nextContentUrl,
                imageStyle: entry.imageStyle,
                payAction: entry.payAction,
                purifySignature: entry.purifySignature,
                cachedAt: date
            ),
            at: 0
        )
        persist()
    }

    func save(_ content: ChapterContent, sourceURL: String, purifyRules: [String]) {
        let entry = ChapterContentCacheEntry(
            key: cacheKey(sourceURL: sourceURL, chapterURL: content.chapter.url),
            sourceURL: sourceURL,
            chapterURL: content.chapter.url,
            bookURL: content.chapter.bookUrl,
            chapterIndex: content.chapter.index,
            title: content.title,
            paragraphs: content.paragraphs,
            nextContentUrl: content.nextContentUrl,
            imageStyle: content.imageStyle,
            payAction: content.payAction,
            purifySignature: purifySignature(purifyRules),
            cachedAt: Date()
        )
        entries.removeAll { $0.key == entry.key }
        entries.insert(entry, at: 0)
        if entries.count > maxEntryCount {
            entries.removeLast(entries.count - maxEntryCount)
        }
        persist()
    }

    func removeExpired(olderThanDays days: Int = 30) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
        entries.removeAll { $0.cachedAt < cutoff }
        persist()
    }

    func removeAll() {
        entries.removeAll()
        persist()
    }

    func remove(key: String) {
        guard entries.contains(where: { $0.key == key }) else { return }
        entries.removeAll { $0.key == key }
        persist()
    }

    /// Drops one chapter after a successful purchase. Legado calls
    /// `BookHelp.delContent(book, chapter)` before reloading the TOC so the
    /// next read cannot fall back to the pre-purchase VIP placeholder.
    func invalidate(sourceURL: String, chapter: BookChapter) {
        remove(key: cacheKey(sourceURL: sourceURL, chapterURL: chapter.url))
    }

    func entries(forBookURL bookURL: String) -> [ChapterContentCacheEntry] {
        entries.filter { $0.bookURL == bookURL }
    }

    func cachedChapters(sourceURL: String, bookURL: String) -> [BookChapter] {
        entries
            .filter { $0.sourceURL == sourceURL && $0.bookURL == bookURL }
            .sorted { lhs, rhs in
                let left = lhs.chapterIndex ?? Int(lhs.chapterURL.split(separator: "#").last ?? "") ?? 0
                let right = rhs.chapterIndex ?? Int(rhs.chapterURL.split(separator: "#").last ?? "") ?? 0
                return left < right
            }
            .map { entry in
                BookChapter(
                    title: entry.title,
                    url: entry.chapterURL,
                    bookUrl: entry.bookURL,
                    index: entry.chapterIndex ?? (Int(entry.chapterURL.split(separator: "#").last ?? "") ?? 0),
                    isVip: false
                )
            }
    }

    private func cacheKey(sourceURL: String, chapterURL: String) -> String {
        "\(sourceURL)|\(chapterURL)"
    }

    private func purifySignature(_ rules: [String]) -> String {
        rules.joined(separator: "\n")
    }

    private func persist() {
        // Both neighbour downloads and an LRU touch used to encode up to 500
        // chapters on the main actor. A TOC could therefore freeze even when
        // the selected chapter was already cached. Immutable COW snapshots
        // are written in order on one disk queue, never on the scroll path.
        persistenceRevision &+= 1
        let revision = persistenceRevision
        persistence.saveInBackground(entries) { [weak self] result in
            let message: String?
            switch result {
            case .success: message = nil
            case .failure(let error): message = error.localizedDescription
            }
            Task { @MainActor [weak self] in
                guard let self, self.persistenceRevision == revision else { return }
                if self.lastError != message { self.lastError = message }
            }
        }
    }
}

struct ChapterContentCachePersistence: Sendable {
    // Shared across instances: reopening the cache flushes preceding writes,
    // and an older store cannot finish a write after a newer store cleared it.
    private static let diskQueue = DispatchQueue(label: "SourceReadSwift.chapter-cache.disk", qos: .utility)
    private let fileManager: FileManager
    private let fileName = "chapter_content_cache.json"
    private let rootURL: URL?

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL
    }

    func load() throws -> [ChapterContentCacheEntry] {
        try Self.diskQueue.sync { try readSnapshot() }
    }

    private func readSnapshot() throws -> [ChapterContentCacheEntry] {
        let url = try storageURL()
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ChapterContentCacheEntry].self, from: data)
    }

    func save(_ entries: [ChapterContentCacheEntry]) throws {
        try Self.diskQueue.sync { try writeSnapshot(entries) }
    }

    /// Completion runs on the writer queue; UI clients must hop to MainActor.
    func saveInBackground(_ entries: [ChapterContentCacheEntry], completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        Self.diskQueue.async {
            completion(Result { try writeSnapshot(entries) })
        }
    }

    private func writeSnapshot(_ entries: [ChapterContentCacheEntry]) throws {
        let url = try storageURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(entries)
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
