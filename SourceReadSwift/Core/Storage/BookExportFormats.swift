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
        for start in stride(from: 0, to: missing.count, by: limit) {
            guard !Task.isCancelled else { break }
            let end = min(start + limit, missing.count)
            let batch = Array(missing[start..<end])
            let results = await withTaskGroup(
                of: (BookChapter, Result<ChapterContent, SourceEngineError>).self
            ) { group in
                for chapter in batch {
                    group.addTask {
                        let result = await ChapterFetchPolicy.fetch(
                            source: source, chapter: chapter, engine: engine)
                        return (chapter, result)
                    }
                }
                var collected: [(BookChapter, Result<ChapterContent, SourceEngineError>)] = []
                for await result in group { collected.append(result) }
                return collected
            }

            for (chapter, result) in results {
                guard !Task.isCancelled else { break }
                guard case .success(let content) = result else { continue }
                contentByURL[chapter.url] = content
                cacheStore.save(content, sourceURL: source.bookSourceUrl,
                                purifyRules: purifyRules)
                completed += 1
            }
            progress(completed, ordered.count)
        }

        return ordered.compactMap { contentByURL[$0.url] }
    }
}
