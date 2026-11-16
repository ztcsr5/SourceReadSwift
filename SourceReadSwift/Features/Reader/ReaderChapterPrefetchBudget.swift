import Foundation

/// Limits speculative chapter requests across readers without blocking foreground navigation.
actor ReaderChapterPrefetchBudget {
    static let shared = ReaderChapterPrefetchBudget(limit: 2)

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let limit: Int
    private var active = 0
    private var waiters: [Waiter] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    /// Keeps the slot until the actual operation returns, even if its caller times out.
    func withSlot<Value: Sendable>(_ operation: @Sendable () async -> Value) async -> Value? {
        let id = UUID()
        guard await acquire(id) else { return nil }
        defer { release() }
        guard !Task.isCancelled else { return nil }
        return await operation()
    }

    static func fetch(using engine: SourceEngine, source: BookSource, chapter: BookChapter) async
        -> Result<ChapterContent, SourceEngineError>? {
        let result = await AsyncTimeout.run(seconds: 12) {
            await shared.withSlot { await engine.getContent(source: source, chapter: chapter) }
        }
        return result ?? nil
    }

    private func acquire(_ id: UUID) async -> Bool {
        guard !Task.isCancelled else { return false }
        if active < limit {
            active += 1
            return true
        }
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                if Task.isCancelled { continuation.resume(returning: false) }
                else { waiters.append(Waiter(id: id, continuation: continuation)) }
            }
        }, onCancel: {
            Task { await self.cancelWaiter(id) }
        })
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }

    private func release() {
        if waiters.isEmpty { active -= 1 }
        else { waiters.removeFirst().continuation.resume(returning: true) }
    }
}
