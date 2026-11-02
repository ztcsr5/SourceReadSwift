import Foundation

/// Cancels provider coordination and rejects results arriving after a cancelled import.
final class FontImportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false
    private var coordinator: NSFileCoordinator?

    func check() throws {
        lock.lock(); let cancelled = isCancelled; lock.unlock()
        if cancelled { throw CancellationError() }
    }

    func coordinate(_ coordinator: NSFileCoordinator) throws {
        lock.lock(); self.coordinator = coordinator; let cancelled = isCancelled; lock.unlock()
        if cancelled { coordinator.cancel(); throw CancellationError() }
    }

    func cancel() {
        lock.lock(); isCancelled = true; let active = coordinator; lock.unlock()
        active?.cancel()
    }
}

/// An unstructured blocking IO task must not keep the UI waiting after its deadline.
enum FontImportRequest {
    private static let queue = DispatchQueue(label: "reader.font-import", qos: .userInitiated)
    private final class Completion: @unchecked Sendable {
        let cancellation = FontImportCancellation()
        private let lock = NSLock()
        private var result: Result<CustomFontItem, Error>?
        private var continuation: CheckedContinuation<CustomFontItem, Error>?

        func attach(_ continuation: CheckedContinuation<CustomFontItem, Error>) {
            lock.lock()
            if let result { lock.unlock(); continuation.resume(with: result) }
            else { self.continuation = continuation; lock.unlock() }
        }

        @discardableResult func finish(_ result: Result<CustomFontItem, Error>) -> Bool {
            lock.lock()
            guard self.result == nil else { lock.unlock(); return false }
            self.result = result; let waiting = continuation; continuation = nil; lock.unlock()
            waiting?.resume(with: result)
            return true
        }
    }

    static func perform(timeout: TimeInterval = 20,
        operation: @escaping @Sendable (FontImportCancellation) throws -> CustomFontItem,
        discard: @escaping @Sendable (CustomFontItem) -> Void = { _ in }) async throws -> CustomFontItem {
        let completion = Completion()
        let deadline = DispatchWorkItem {
            if completion.finish(.failure(NSError(domain: "FontImport", code: 8,
                userInfo: [NSLocalizedDescriptionKey: "字体处理超过 20 秒，已停止等待。原字体未改变，请重试或换一份字体文件。"]))) {
                completion.cancellation.cancel()
            }
        }
        defer { deadline.cancel() }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                completion.attach(continuation)
                queue.async {
                    let outcome = Result { try completion.cancellation.check(); return try operation(completion.cancellation) }
                    if !completion.finish(outcome), case .success(let item) = outcome { discard(item) }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(timeout, 0.01), execute: deadline)
            }
        }, onCancel: {
            completion.cancellation.cancel()
            completion.finish(.failure(CancellationError()))
        })
    }
}
