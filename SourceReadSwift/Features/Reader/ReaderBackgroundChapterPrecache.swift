import Foundation

/// Owns one disk-only chapter queue; replacement and reader exit invalidate late results.
@MainActor
final class ReaderBackgroundChapterPrecache {
    private struct PendingLoad: Sendable {
        let id: UUID
        let chapter: BookChapter
        let task: Task<Result<ChapterContent, SourceEngineError>?, Never>
    }

    private var task: Task<Void, Never>?
    private var requestKey: String?
    private var pendingLoad: PendingLoad?

    nonisolated init() {}

    func start(key: String, chapters: [BookChapter],
               load: @escaping @MainActor (BookChapter) async -> Result<ChapterContent, SourceEngineError>?,
               commit: @escaping @MainActor (ChapterContent) -> Void) {
        guard requestKey != key else { return }
        cancel()
        requestKey = key
        task = Task(priority: .utility) { @MainActor [weak self] in
            for chapter in chapters {
                guard !Task.isCancelled, self?.requestKey == key else { return }
                let id = UUID()
                let request = Task { @MainActor in await load(chapter) }
                self?.pendingLoad = PendingLoad(id: id, chapter: chapter, task: request)
                let result = await request.value
                if self?.pendingLoad?.id == id { self?.pendingLoad = nil }
                guard !Task.isCancelled, self?.requestKey == key else { return }
                switch result {
                case .success(let content)?: commit(content)
                case .failure(.empty(_))?, nil: break
                case .failure(let error)?:
                    guard !SourceDiagnosticClassifier.shouldPauseRequests(after: error) else { return }
                }
                await Task.yield()
            }
        }
    }

    func hasPendingLoad(for chapter: BookChapter) -> Bool {
        pendingLoad?.chapter.url == chapter.url && pendingLoad?.chapter.bookUrl == chapter.bookUrl
    }

    /// A foreground reader owns this request now; cancelling the old queue must not cancel it.
    func takePendingResult(for chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError>? {
        guard hasPendingLoad(for: chapter), let pending = pendingLoad else { return nil }
        pendingLoad = nil
        cancel()
        return await withTaskCancellationHandler(operation: { await pending.task.value },
            onCancel: { pending.task.cancel() })
    }

    func cancel() {
        requestKey = nil
        task?.cancel()
        task = nil
        pendingLoad?.task.cancel()
        pendingLoad = nil
    }

    deinit { task?.cancel(); pendingLoad?.task.cancel() }
}
