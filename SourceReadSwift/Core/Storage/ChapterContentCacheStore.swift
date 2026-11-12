import Foundation

/// A book URL can be shared by independent sources with different cached chapters.
struct OfflineChapterEdition: Identifiable {
    struct Identity: Hashable {
        let bookURL: String
        let sourceURL: String
    }

    let id: Identity
    let entries: [ChapterContentCacheEntry]

    static func group(_ entries: [ChapterContentCacheEntry]) -> [Self] {
        Dictionary(grouping: entries) { Identity(bookURL: $0.bookURL, sourceURL: $0.sourceURL) }
            .map { id, chapters in
                Self(id: id, entries: chapters.sorted {
                    $0.cachedAt == $1.cachedAt ? $0.key < $1.key : $0.cachedAt > $1.cachedAt
                })
            }
            .sorted { ($0.id.bookURL, $0.id.sourceURL) < ($1.id.bookURL, $1.id.sourceURL) }
    }
}

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
    /// Explicit offline downloads are not disposable reading-prefetch entries. Nil decodes old cache files.
    let isOffline: Bool?

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
        cachedAt: Date,
        isOffline: Bool? = nil
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
        self.isOffline = isOffline
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
    /// Membership changes publish through `objectWillChange`; the LRU touch in
    /// `markRead` deliberately does not. AppState does not observe this store,
    /// so the only subscriber is the offline-cache screen; keeping the touch
    /// silent avoids invalidating it for every chapter the reader crosses.
    private(set) var entries: [ChapterContentCacheEntry] = []
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
        self.maxEntryCount = max(0, maxEntryCount)
        do {
            entries = try persistence.load()
            trimPrefetchEntries()
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

    /// Snapshot existing cached URLs without rebuilding chapter bodies or touching the LRU.
    func cachedChapterURLs(sourceURL: String, purifyRules: [String]) -> Set<String> {
        let signature = purifySignature(purifyRules)
        return Set(entries.lazy.filter {
            $0.sourceURL == sourceURL && $0.purifySignature == signature
        }.map(\.chapterURL))
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
        var nextEntries = entries
        let entry = nextEntries.remove(at: index)
        nextEntries.insert(
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
                cachedAt: date,
                isOffline: entry.isOffline
            ),
            at: 0
        )
        entries = nextEntries
        persist()
    }

    func save(_ content: ChapterContent, sourceURL: String, purifyRules: [String], retainOffline: Bool = false) {
        // Prefetch saves one chapter every few seconds while the reader is
        // scrolling. `AppState` does not observe this store, but an offscreen
        // settings/offline-cache screen would still be invalidated on every
        // write. Membership changes stay explicit; the offline list recomputes
        // when it appears instead of during reading.
        let key = cacheKey(sourceURL: sourceURL, chapterURL: content.chapter.url)
        let isOffline = retainOffline || entries.contains { $0.key == key && $0.isOffline == true }
        let entry = ChapterContentCacheEntry(
            key: key,
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
            cachedAt: Date(),
            isOffline: isOffline ? true : nil
        )
        objectWillChange.send()
        entries.removeAll { $0.key == entry.key }
        entries.insert(entry, at: 0)
        trimPrefetchEntries()
        persist()
    }

    private func trimPrefetchEntries() {
        var retainedPrefetchCount = 0
        entries.removeAll { entry in
            guard entry.isOffline != true else { return false }
            retainedPrefetchCount += 1
            return retainedPrefetchCount > maxEntryCount
        }
    }

    /// Downloads only report durable success after the writer acknowledges the current snapshot.
    func flush() async throws {
        try await persistence.waitForPendingWrites()
    }

    func removeExpired(olderThanDays days: Int = 30) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
        guard entries.contains(where: { $0.isOffline != true && $0.cachedAt < cutoff }) else { return }
        objectWillChange.send()
        entries.removeAll { $0.isOffline != true && $0.cachedAt < cutoff }
        persist()
    }

    func removeAll() {
        guard !entries.isEmpty else { return }
        objectWillChange.send()
        entries.removeAll()
        persist()
    }

    func remove(key: String) {
        guard entries.contains(where: { $0.key == key }) else { return }
        objectWillChange.send()
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
    private static let pendingWrites = PendingWrites()
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
        try Self.diskQueue.sync {
            try writeSnapshot(entries)
            Self.pendingWrites.lastResults[try storageURL()] = Result<Void, Error>(catching: {})
        }
    }

    /// Completion runs on the writer queue; UI clients must hop to MainActor.
    func saveInBackground(_ entries: [ChapterContentCacheEntry], completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        let url: URL
        do { url = try storageURL() }
        catch { completion(.failure(error)); return }
        Self.pendingWrites.lock.lock()
        if var pending = Self.pendingWrites.snapshots[url] {
            pending.entries = entries
            pending.completions.append(completion)
            Self.pendingWrites.snapshots[url] = pending
        } else {
            Self.pendingWrites.snapshots[url] = PendingSnapshot(entries: entries, completions: [completion])
            Self.diskQueue.async {
                Self.pendingWrites.lock.lock()
                let pending = Self.pendingWrites.snapshots.removeValue(forKey: url)
                Self.pendingWrites.lock.unlock()
                guard let pending else { return }
                let result = Result { try writeSnapshot(pending.entries) }
                Self.pendingWrites.lastResults[url] = result
                pending.completions.forEach { $0(result) }
            }
        }
        Self.pendingWrites.lock.unlock()
    }

    /// A serialization barrier reports the actual writer result without encoding the same book twice.
    func waitForPendingWrites() async throws {
        let url = try storageURL()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Self.diskQueue.async {
                let result = Self.pendingWrites.lastResults[url] ?? Result<Void, Error>(catching: {})
                continuation.resume(with: result)
            }
        }
    }

    private struct PendingSnapshot {
        var entries: [ChapterContentCacheEntry]
        var completions: [@Sendable (Result<Void, Error>) -> Void]
    }

    private final class PendingWrites: @unchecked Sendable {
        let lock = NSLock()
        var snapshots: [URL: PendingSnapshot] = [:]
        // Accessed only on diskQueue, including barriers.
        var lastResults: [URL: Result<Void, Error>] = [:]
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
