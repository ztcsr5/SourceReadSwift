import Foundation

extension BookExportService {
    /// Unified entry point for the three user-visible export formats.
    /// Chapter fetching stays outside the service so packaging never blocks a
    /// view transition on the network.
    func exportBook(
        book: BookshelfBook,
        cachedChapters: [ChapterContent],
        format: BookExportFormat,
        coverJPEG: Data?,
        totalChapterCount: Int = 0
    ) throws -> BookArchiveExport {
        try Task.checkCancellation()
        guard !cachedChapters.isEmpty else { throw BookExportError.noContent }
        let total = max(totalChapterCount, cachedChapters.count)
        switch format {
        case .txt:
            let url = try exportBookToPlainText(book: book, cachedChapters: cachedChapters)
            return BookArchiveExport(url: url, format: .txt,
                exportedChapterCount: cachedChapters.count, totalChapterCount: total)
        case .zip:
            return try exportBookArchive(book: book, cachedChapters: cachedChapters,
                coverJPEG: coverJPEG, totalChapterCount: total)
        case .epub:
            return try BookEPUBWriter().export(book: book, chapters: cachedChapters,
                coverJPEG: coverJPEG, totalChapterCount: total)
        }
    }
}

/// Fetches the chapters needed by an export without relying on the 500-entry
/// reading cache. Results are accumulated in memory so a long book cannot
/// evict its own opening chapters while the export is still running.
@MainActor
enum BookExportChapterLoader {
    static func load(
        chapters: [BookChapter],
        cachedChapters: [ChapterContent],
        source: BookSource,
        engine: SourceEngine,
        cacheStore: ChapterContentCacheStore,
        purifyRules: [String],
        progress: (Int, Int) -> Void
    ) async -> [ChapterContent] {
        let ordered = chapters.enumerated().sorted {
            if $0.element.index != $1.element.index {
                return $0.element.index < $1.element.index
            }
            return $0.offset < $1.offset
        }.map(\.element)
        guard !ordered.isEmpty else { return [] }

        var contentByURL: [String: ChapterContent] = [:]
        for content in cachedChapters {
            contentByURL[content.chapter.url] = content
        }
        let missing = ordered.filter { contentByURL[$0.url] == nil }
        var completed = ordered.count - missing.count
        progress(completed, ordered.count)

        let limit = max(1, ChapterFetchPolicy.concurrentRequestLimit)
        var cursor = 0
        await withTaskGroup(of: ChapterFetchOutcome.self) { group in
            for _ in 0..<limit {
                guard cursor < missing.count else { break }
                let chapter = missing[cursor]
                cursor += 1
                group.addTask { (chapter, await ChapterFetchPolicy.fetch(source: source, chapter: chapter, engine: engine)) }
            }
            while let (chapter, result) = await group.next() {
                guard !Task.isCancelled else { group.cancelAll(); break }
                if case .success(let content) = result {
                    contentByURL[chapter.url] = content
                    cacheStore.save(content, sourceURL: source.bookSourceUrl, purifyRules: purifyRules)
                    completed += 1
                }
                progress(completed, ordered.count)
                guard cursor < missing.count else { continue }
                let next = missing[cursor]
                cursor += 1
                group.addTask { (next, await ChapterFetchPolicy.fetch(source: source, chapter: next, engine: engine)) }
            }
        }

        return ordered.compactMap { contentByURL[$0.url] }
    }
}
