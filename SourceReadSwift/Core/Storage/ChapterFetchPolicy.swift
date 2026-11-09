import Foundation

/// Shared retry and concurrency policy for whole-book chapter transfers.
///
/// Source rules often fail once on a transient HTTP/JS condition and succeed
/// immediately when retried. The old serial downloader turned that into a
/// permanently failed chapter and made a 1000-chapter book take a full request
/// timeout per bad link. Keep one bounded policy for downloads and exports.
enum ChapterFetchPolicy {
    static let concurrentRequestLimit = 3
    static let requestTimeout: Double = 15
    static let maximumAttempts = 3
    private static let retryDelaysNanoseconds: [UInt64] = [800_000_000, 1_600_000_000]

    static func fetch(
        source: BookSource,
        chapter: BookChapter,
        engine: SourceEngine
    ) async -> Result<ChapterContent, SourceEngineError> {
        guard !Task.isCancelled else { return .failure(.network("章节请求已取消")) }
        var lastError: SourceEngineError = .network("章节请求超时")

        for attempt in 0..<maximumAttempts {
            guard !Task.isCancelled else { return .failure(.network("章节请求已取消")) }
            let result = await AsyncTimeout.run(seconds: requestTimeout) {
                await engine.getContent(source: source, chapter: chapter)
            }
            switch result {
            case .some(.success(let content)):
                return .success(content)
            case .some(.failure(let error)):
                guard shouldRetry(error) else { return .failure(error) }
                lastError = error
            case .none:
                lastError = .network("章节请求超时")
            }

            guard attempt + 1 < maximumAttempts else { break }
            let delay = retryDelaysNanoseconds[min(attempt, retryDelaysNanoseconds.count - 1)]
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return .failure(.network("章节请求已取消"))
            }
        }
        return .failure(lastError)
    }

    /// Rule and JavaScript failures are deterministic for a given chapter.
    /// Retrying them only delayed the rest of the queue.
    private static func shouldRetry(_ error: SourceEngineError) -> Bool {
        switch error {
        case .network, .blocked, .empty:
            return true
        case .unsupported, .invalidSource, .rule, .javascript:
            return false
        }
    }
}
