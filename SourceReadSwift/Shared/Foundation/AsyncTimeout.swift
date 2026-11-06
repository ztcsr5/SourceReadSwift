import Foundation

enum AsyncTimeout {
    static func run<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async -> T
    ) async -> T? {
        guard !Task.isCancelled, seconds.isFinite, seconds > 0 else { return nil }
        // Bound the conversion below UInt64.max even for externally supplied values.
        let maximumSeconds = Double(UInt64.max / 1_000_000_000)
        let nanoseconds = UInt64(min(seconds, maximumSeconds) * 1_000_000_000)
        let race = TimeoutCompletion<T>()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                guard race.install(continuation) else { return }
                let worker = Task {
                    guard !Task.isCancelled, !race.isFinished else { return }
                    race.finish(await operation())
                }
                let timer = Task {
                    do { try await Task.sleep(nanoseconds: nanoseconds) }
                    catch { return }
                    race.finish(nil)
                }
                race.installTasks(worker: worker, timer: timer)
            }
        }, onCancel: { race.finish(nil) })
    }
}

/// Resumes the waiter once; a noncooperative worker may finish later but cannot publish again.
private final class TimeoutCompletion<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?
    private var hasFinished = false
    private var result: Value?
    private var worker: Task<Void, Never>?
    private var timer: Task<Void, Never>?

    var isFinished: Bool {
        lock.lock(); defer { lock.unlock() }
        return hasFinished
    }

    func install(_ continuation: CheckedContinuation<Value?, Never>) -> Bool {
        lock.lock()
        if hasFinished {
            let result = result
            lock.unlock()
            continuation.resume(returning: result)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func installTasks(worker: Task<Void, Never>, timer: Task<Void, Never>) {
        lock.lock()
        if hasFinished {
            lock.unlock()
            worker.cancel()
            timer.cancel()
            return
        }
        self.worker = worker
        self.timer = timer
        lock.unlock()
    }

    func finish(_ result: Value?) {
        lock.lock()
        guard !hasFinished else { lock.unlock(); return }
        hasFinished = true
        self.result = result
        let pending = continuation
        continuation = nil
        let worker = worker, timer = timer
        self.worker = nil
        self.timer = nil
        lock.unlock()
        worker?.cancel()
        timer?.cancel()
        pending?.resume(returning: result)
    }
}
