import Foundation

/// Launch and manual refresh share one bounded pass. Metadata lands in a single shelf update.
@MainActor
final class BookshelfChapterRefreshCoordinator {
    struct Summary: Equatable, Sendable {
        let attempted: Int
        let checked: Int
    }

    private struct Candidate: Sendable {
        let shelfID: String
        let book: SearchBook
        let source: BookSource
    }

    private let shelf: BookshelfStore
    private let sources: SourceStore
    private let engine: SourceEngine
    private var hasStartedOnLaunch = false
    private var activeRefresh: Task<Summary, Never>?

    init(shelf: BookshelfStore, sources: SourceStore, engine: SourceEngine) {
        self.shelf = shelf
        self.sources = sources
        self.engine = engine
    }

    func refreshOnLaunch() async {
        guard !hasStartedOnLaunch, !Task.isCancelled else { return }
        hasStartedOnLaunch = true
        _ = await refresh()
    }

    func refresh() async -> Summary {
        if let activeRefresh { return await activeRefresh.value }
        let task = Task(priority: .utility) {
            let candidates = makeCandidates()
            let observations = await Self.check(candidates, engine: engine)
            shelf.applyChapterRefresh(observations)
            return Summary(attempted: candidates.count, checked: observations.count)
        }
        activeRefresh = task
        let summary = await task.value
        activeRefresh = nil
        return summary
    }

    private func makeCandidates() -> [Candidate] {
        let enabledByURL = Dictionary(sources.sources.filter(\.enabled).map { ($0.bookSourceUrl, $0) },
                                      uniquingKeysWith: { first, _ in first })
        return shelf.books.compactMap { book in
            guard !book.sourceURL.hasPrefix("local://"), let source = enabledByURL[book.sourceURL] else { return nil }
            return Candidate(shelfID: book.id, book: book.asSearchBook, source: source.resolvingMediaKind(book.mediaKind))
        }
    }

    nonisolated private static func check(_ candidates: [Candidate], engine: SourceEngine) async -> [BookshelfChapterObservation] {
        await withTaskGroup(of: BookshelfChapterObservation?.self) { group in
            var remaining = candidates.makeIterator()
            let parallelBooks = 4
            for _ in 0..<parallelBooks {
                guard let candidate = remaining.next() else { break }
                group.addTask { await fetch(candidate, engine: engine) }
            }
            var checked: [BookshelfChapterObservation] = []
            while let outcome = await group.next() {
                guard !Task.isCancelled else { group.cancelAll(); break }
                if let outcome { checked.append(outcome) }
                if let next = remaining.next() {
                    group.addTask { await fetch(next, engine: engine) }
                }
            }
            return checked
        }
    }

    nonisolated private static func fetch(_ candidate: Candidate, engine: SourceEngine) async -> BookshelfChapterObservation? {
        let timeout: Double = 12
        guard case .success(let detail)? = await AsyncTimeout.run(seconds: timeout, operation: {
            await engine.getBookDetail(source: candidate.source, book: candidate.book)
        }) else { return nil }
        guard case .success(let chapters)? = await AsyncTimeout.run(seconds: timeout, operation: {
            await engine.getChapterList(source: candidate.source, book: detail)
        }), !chapters.isEmpty, !Task.isCancelled else { return nil }
        let metadata = BookshelfBookDetails(latestChapterTitle: chapters.last?.title ?? detail.latestChapter,
            intro: detail.intro, totalChapters: chapters.count, coverURL: detail.coverUrl, mediaKind: detail.mediaKind)
        return .init(shelfID: candidate.shelfID, book: candidate.book, details: metadata)
    }
}
