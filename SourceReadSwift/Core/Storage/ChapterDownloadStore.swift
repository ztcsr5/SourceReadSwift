import Foundation
import Combine

/// 章节抓取结果的元组别名。直接写 `(A, Result<B, C>).self` 作为
/// `withTaskGroup(of:)` 的泛型实参时，语法审计用的 tree-sitter 会把
/// 元组 metatype 误判为语法错误；起一个名字既避开误报，也更好读。
typealias ChapterFetchOutcome = (BookChapter, Result<ChapterContent, SourceEngineError>)

/// A resumable whole-book download record.  Only chapter indexes and
/// diagnostics are persisted; network credentials remain in SourceCookieStore.
struct ChapterDownloadRecord: Identifiable, Codable, Hashable, Sendable {
    enum Status: String, Codable, Hashable, Sendable {
        case queued
        case running
        case paused
        case completed
        case failed
        case cancelled
    }

    let id: String
    var sourceURL: String
    var bookURL: String
    var title: String
    var chapterCount: Int
    var hasComicImageArchive: Bool?
    var completedIndexes: [Int]
    var failedIndexes: [Int]
    var status: Status
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date

    var completedCount: Int { completedIndexes.count }
    var failedCount: Int { failedIndexes.count }
    var progress: Double {
        guard chapterCount > 0 else { return 0 }
        return min(max(Double(completedCount) / Double(chapterCount), 0), 1)
    }

    init(
        id: String,
        sourceURL: String,
        bookURL: String,
        title: String,
        chapterCount: Int,
        hasComicImageArchive: Bool? = nil,
        completedIndexes: [Int] = [],
        failedIndexes: [Int] = [],
        status: Status = .queued,
        lastError: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.bookURL = bookURL
        self.title = title
        self.chapterCount = max(0, chapterCount)
        self.hasComicImageArchive = hasComicImageArchive
        self.completedIndexes = Array(Set(completedIndexes.filter { $0 >= 0 })).sorted()
        self.failedIndexes = Array(Set(failedIndexes.filter { $0 >= 0 })).sorted()
        self.status = status
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ChapterDownloadPersistence {
    private let fileManager: FileManager
    private let fileName = "chapter_downloads.json"
    private let rootURL: URL?

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL
    }

    func load() throws -> [String: ChapterDownloadRecord] {
        let url = try storageURL()
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var records = try decoder.decode([String: ChapterDownloadRecord].self, from: Data(contentsOf: url))
        // A process can be killed while a task is running.  Treat that as a
        // resumable pause instead of leaving a permanently spinning record.
        for key in records.keys where records[key]?.status == .running {
            records[key]?.status = .paused
            records[key]?.updatedAt = Date()
        }
        return records
    }

    func save(_ records: [String: ChapterDownloadRecord]) throws {
        let url = try storageURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(records).write(to: url, options: [.atomic])
    }

    private func storageURL() throws -> URL {
        if let rootURL { return rootURL.appendingPathComponent(fileName) }
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("SourceReadSwift", isDirectory: true).appendingPathComponent(fileName)
    }
}

@MainActor
final class ChapterDownloadStore: ObservableObject {
    @Published private(set) var records: [String: ChapterDownloadRecord] = [:]
    @Published private(set) var lastError: String?

    private let persistence: ChapterDownloadPersistence

    init(persistence: ChapterDownloadPersistence = ChapterDownloadPersistence()) {
        self.persistence = persistence
        do {
            records = try persistence.load()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func record(bookID: String) -> ChapterDownloadRecord? { records[bookID] }

    func begin(
        bookID: String,
        sourceURL: String,
        bookURL: String,
        title: String,
        chapterCount: Int,
        hasComicImageArchive: Bool? = nil,
        cachedChapterIndexes: [Int]? = nil
    ) {
        let old = records[bookID]
        let canResume = old?.sourceURL == sourceURL && old?.bookURL == bookURL && old?.chapterCount == chapterCount
        records[bookID] = ChapterDownloadRecord(
            id: bookID,
            sourceURL: sourceURL,
            bookURL: bookURL,
            title: title,
            chapterCount: chapterCount,
            hasComicImageArchive: hasComicImageArchive,
            completedIndexes: cachedChapterIndexes ?? (canResume ? (old?.completedIndexes ?? []) : []),
            failedIndexes: [],
            status: .queued,
            lastError: nil,
            createdAt: old?.createdAt ?? Date(),
            updatedAt: Date()
        )
        persist()
    }

    func markRunning(bookID: String) { update(bookID) { $0.status = .running; $0.lastError = nil } }
    func markPaused(bookID: String) { update(bookID) { $0.status = .paused } }
    func markCancelled(bookID: String) { update(bookID) { $0.status = .cancelled } }

    func markCompleted(bookID: String, chapterIndex: Int) {
        update(bookID) {
            $0.completedIndexes = Array(Set($0.completedIndexes + [chapterIndex])).sorted()
            $0.failedIndexes.removeAll { $0 == chapterIndex }
            $0.lastError = nil
        }
    }

    func markFailed(bookID: String, chapterIndex: Int, message: String) {
        update(bookID) {
            $0.failedIndexes = Array(Set($0.failedIndexes + [chapterIndex])).sorted()
            $0.lastError = message
            $0.status = .failed
        }
    }

    func finish(bookID: String) {
        update(bookID) {
            $0.status = $0.failedIndexes.isEmpty ? .completed : .failed
        }
    }

    func remove(bookID: String) {
        records.removeValue(forKey: bookID)
        persist()
    }

    func removeComicRecords() {
        records = records.filter { $0.value.hasComicImageArchive != true }
        persist()
    }

    private func update(_ bookID: String, _ mutation: (inout ChapterDownloadRecord) -> Void) {
        guard var record = records[bookID] else { return }
        mutation(&record)
        record.updatedAt = Date()
        records[bookID] = record
        persist()
    }

    private func persist() {
        do {
            try persistence.save(records)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

/// Owns long-running cache jobs outside a view lifetime.  This prevents a
/// detail sheet disappearing from silently losing a whole-book download and
/// lets the next launch resume from the persisted chapter indexes.
@MainActor
final class ChapterDownloadCoordinator: ObservableObject {
    private struct DownloadJob {
        let generation: UUID
        let task: Task<Void, Never>
    }

    private let store: ChapterDownloadStore
    private let comicArchive: ComicOfflineArchive
    private let fetchComicPage: ComicOfflineArchive.PageFetcher
    private var tasks: [String: DownloadJob] = [:]

    init(store: ChapterDownloadStore, comicArchive: ComicOfflineArchive = .shared,
         fetchComicPage: @escaping ComicOfflineArchive.PageFetcher = { await RemoteImageLoader.shared.comicBytesForArchive($0) }) {
        self.store = store
        self.comicArchive = comicArchive
        self.fetchComicPage = fetchComicPage
    }

    func isRunning(bookID: String) -> Bool { tasks[bookID] != nil }

    func start(
        bookID: String,
        source: BookSource,
        title: String,
        chapters: [BookChapter],
        engine: SourceEngine,
        cacheStore: ChapterContentCacheStore,
        purifyRules: [String]
    ) {
        guard !chapters.isEmpty, tasks[bookID] == nil else { return }
        let generation = UUID()
        let isComic = source.sourceKind == .comic
        let cachedURLs = isComic ? [] : cacheStore.cachedChapterURLs(sourceURL: source.bookSourceUrl, purifyRules: purifyRules)
        let completed = Set(chapters.lazy.filter { cachedURLs.contains($0.url) }.map(\.index))
        store.begin(
            bookID: bookID,
            sourceURL: source.bookSourceUrl,
            bookURL: chapters[0].bookUrl,
            title: title,
            chapterCount: chapters.count,
            hasComicImageArchive: isComic ? true : nil,
            cachedChapterIndexes: Array(completed)
        )
        store.markRunning(bookID: bookID)
        let task = Task { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            if isComic {
                // Comic archives hold image data in a separate store. Keep their
                // writes serialized; text chapters use the bounded batch below.
                for chapter in chapters {
                    guard self.isCurrentJob(bookID, generation: generation) else { return }
                    guard !completed.contains(chapter.index) else { continue }
                    await self.downloadComic(chapter, plan: (bookID, generation, source, engine))
                }
            } else {
                let pending = chapters.filter { !completed.contains($0.index) }
                let limit = max(1, ChapterFetchPolicy.concurrentRequestLimit)
                var nextChapter = 0
                // Keep the window full: one slow chapter used to block the two
                // completed results beside it until every request in the batch
                // returned, which made a 1000-chapter cache look stalled.
                await withTaskGroup(of: ChapterFetchOutcome.self) { group in
                    for _ in 0..<limit {
                        guard nextChapter < pending.count else { break }
                        let chapter = pending[nextChapter]
                        nextChapter += 1
                        group.addTask {
                            let result = await ChapterFetchPolicy.fetch(
                                source: source, chapter: chapter, engine: engine)
                            return (chapter, result)
                        }
                    }
                    while let finished = await group.next() {
                        let chapter = finished.0
                        let result = finished.1
                        guard self.isCurrentJob(bookID, generation: generation) else {
                            group.cancelAll()
                            return
                        }
                        switch result {
                        case .success(let content):
                            cacheStore.save(content, sourceURL: source.bookSourceUrl,
                                             purifyRules: purifyRules)
                            store.markCompleted(bookID: bookID, chapterIndex: chapter.index)
                        case .failure(let error):
                            store.markFailed(bookID: bookID, chapterIndex: chapter.index,
                                              message: error.displayMessage)
                        }
                        guard nextChapter < pending.count else { continue }
                        let following = pending[nextChapter]
                        nextChapter += 1
                        group.addTask {
                            let followingResult = await ChapterFetchPolicy.fetch(
                                source: source, chapter: following, engine: engine)
                            return (following, followingResult)
                        }
                    }
                }
            }
            guard self.isCurrentJob(bookID, generation: generation) else { return }
            store.finish(bookID: bookID)
            self.tasks.removeValue(forKey: bookID)
        }
        tasks[bookID] = DownloadJob(generation: generation, task: task)
    }

    private func downloadComic(_ chapter: BookChapter,
                               plan: (bookID: String, generation: UUID, source: BookSource, engine: SourceEngine)) async {
        let sourceURL = plan.source.bookSourceUrl
        let saved = await comicArchive.contains(sourceURL: sourceURL, chapter: chapter)
        guard isCurrentJob(plan.bookID, generation: plan.generation) else { return }
        if saved {
            store.markCompleted(bookID: plan.bookID, chapterIndex: chapter.index)
            return
        }
        let response = await AsyncTimeout.run(seconds: 30) {
            await plan.engine.getContent(source: plan.source, chapter: chapter)
        } ?? .failure(.network("漫画章节请求超时"))
        guard isCurrentJob(plan.bookID, generation: plan.generation) else { return }
        do {
            let content = try response.get()
            let headers = SourceRequestBuilder().imageRequestHeaders(for: plan.source, chapterURL: chapter.url)
            try await comicArchive.save(content, sourceURL: sourceURL, headers: headers, fetch: fetchComicPage)
            guard isCurrentJob(plan.bookID, generation: plan.generation) else { return }
            store.markCompleted(bookID: plan.bookID, chapterIndex: chapter.index)
        } catch {
            guard isCurrentJob(plan.bookID, generation: plan.generation) else { return }
            let message = (error as? SourceEngineError)?.displayMessage ?? error.localizedDescription
            store.markFailed(bookID: plan.bookID, chapterIndex: chapter.index, message: message)
        }
    }

    private func isCurrentJob(_ bookID: String, generation: UUID) -> Bool {
        !Task.isCancelled && tasks[bookID]?.generation == generation
    }

    /// Invalidates active jobs before clearing their offline chapters.
    func cancelAll() {
        for bookID in Array(tasks.keys) { cancel(bookID: bookID) }
    }

    /// Ordinary chapter-cache cleanup must not interrupt independent image archives.
    func cancelChapterCacheDownloads() {
        for bookID in Array(tasks.keys) where store.record(bookID: bookID)?.hasComicImageArchive != true {
            cancel(bookID: bookID)
        }
    }

    func cancelComicDownloads() {
        for bookID in Array(tasks.keys) where store.record(bookID: bookID)?.hasComicImageArchive == true {
            cancel(bookID: bookID)
        }
    }

    /// Cancel this generation only; callers can optionally await network cleanup.
    @discardableResult func cancel(bookID: String) -> Task<Void, Never>? {
        let job = tasks.removeValue(forKey: bookID)
        job?.task.cancel()
        store.markCancelled(bookID: bookID)
        return job?.task
    }
}
