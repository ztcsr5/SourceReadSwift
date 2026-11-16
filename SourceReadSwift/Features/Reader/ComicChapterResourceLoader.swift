import Foundation

/// Adapts the paper reader's existing JSON/offline resources, not Aidoku's source extensions.
@MainActor
struct ComicChapterResourceLoader {
    let source: BookSource
    let engine: SourceEngine
    let store: ChapterContentCacheStore
    let archive: ComicOfflineArchive

    struct Outcome {
        var resources: ComicChapterResources?
        var error: String?
    }

    func load(_ chapter: BookChapter, rules: [String], forcesRefresh: Bool, isSpeculative: Bool) async -> Outcome {
        if let engine = engine as? LocalComicSourceEngine {
            let pages = engine.pages(for: chapter)
            return pages.isEmpty ? Outcome(error: "本地漫画图片不存在，请返回书架重新导入。")
                : Outcome(resources: ComicChapterResources(offlinePages: pages))
        }
        let isOffline = ComicOfflineArchive.isOfflineChapter(chapter)
        if !forcesRefresh || isOffline {
            if let pages = await archive.pages(sourceURL: source.bookSourceUrl, chapter: chapter) {
                return Outcome(resources: ComicChapterResources(offlinePages: pages))
            }
            if isOffline { return Outcome(error: "离线图片已丢失，请返回详情重新下载本话。") }
        }

        let cached = store.content(sourceURL: source.bookSourceUrl, chapter: chapter, purifyRules: rules)
        let previous = await Self.decode(cached)
        if !forcesRefresh, previous?.canReuseFromCache == true { return Outcome(resources: previous) }
        guard !Task.isCancelled else { return Outcome() }

        let result: Result<ChapterContent, SourceEngineError>?
        if isSpeculative { result = await ReaderChapterPrefetchBudget.fetch(using: engine, source: source, chapter: chapter) }
        else { result = await engine.getContent(source: source, chapter: chapter) }
        guard !Task.isCancelled else { return Outcome() }
        switch result {
        case .success(let content):
            guard let resources = await Self.decode(content), !resources.pages.isEmpty, !Task.isCancelled else {
                return Outcome(error: "未在当前章节解析到漫画图片")
            }
            if resources.canReuseFromCache { store.save(content, sourceURL: source.bookSourceUrl, purifyRules: rules) }
            return Outcome(resources: resources)
        case .failure(let error):
            return Outcome(resources: previous, error: error.displayMessage)
        case nil:
            return Outcome(error: "本话预取超时，可重试或换源。")
        }
    }

    private static func decode(_ content: ChapterContent?) async -> ComicChapterResources? {
        guard let content, !Task.isCancelled else { return nil }
        return await Task.detached(priority: .userInitiated) { ComicChapterResources(content: content) }.value
    }
}
