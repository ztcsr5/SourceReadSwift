import Foundation

/// Owns one disk-only chapter queue; replacement and reader exit invalidate late results.
@MainActor
final class ReaderBackgroundChapterPrecache {
    private var task: Task<Void, Never>?
    private var requestKey: String?

    nonisolated init() {}

    func start(key: String, chapters: [BookChapter],
               load: @escaping @MainActor (BookChapter) async -> ChapterContent?,
               commit: @escaping @MainActor (ChapterContent) -> Void) {
        guard requestKey != key else { return }
        cancel()
        requestKey = key
        task = Task(priority: .utility) { @MainActor [weak self] in
            for chapter in chapters {
                guard !Task.isCancelled, self?.requestKey == key else { return }
                let content = await load(chapter)
                guard !Task.isCancelled, self?.requestKey == key else { return }
                if let content { commit(content) }
                await Task.yield()
            }
        }
    }

    func cancel() {
        requestKey = nil
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}
