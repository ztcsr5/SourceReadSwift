import Foundation

/// Reads comic responses in URLSession chunks so rejected bodies never reach image decoding.
final class ComicImageTransport: Sendable {
    private let session: URLSession
    private let receiver: ComicImageReceiver

    init(configuration: URLSessionConfiguration) {
        let receiver = ComicImageReceiver(limit: ComicOfflineArchive.maximumPageBytes)
        self.receiver = receiver
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        self.session = URLSession(configuration: configuration, delegate: receiver, delegateQueue: delegateQueue)
    }

    deinit { session.invalidateAndCancel() }

    func load(_ request: URLRequest) async -> Result<Data, ComicImageFailure> {
        guard !Task.isCancelled else { return .failure(.cancelled) }
        let cancellation = ComicTransferCancellation()
        let result: Result<Data, ComicImageFailure> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let task = session.dataTask(with: request)
                receiver.register(task, continuation: continuation)
                cancellation.start(task)
            }
        } onCancel: {
            cancellation.cancel()
        }
        return Task.isCancelled ? .failure(.cancelled) : result
    }
}

/// Install before starting or cancelling the underlying suspended task.
private final class ComicTransferCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var isCancelled = false

    func start(_ task: URLSessionDataTask) {
        lock.lock()
        self.task = task
        let wasCancelled = isCancelled
        lock.unlock()
        if wasCancelled { task.cancel() } else { task.resume() }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let activeTask = task
        lock.unlock()
        activeTask?.cancel()
    }
}

/// Delegate callbacks are serial; the lock guards only the table shared with task creation.
private final class ComicImageReceiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private final class Transfer {
        var bytes = Data()
        let continuation: CheckedContinuation<Result<Data, ComicImageFailure>, Never>

        init(_ continuation: CheckedContinuation<Result<Data, ComicImageFailure>, Never>) {
            self.continuation = continuation
        }
    }

    private let lock = NSLock()
    private let limit: Int
    private var transfers: [Int: Transfer] = [:]

    init(limit: Int) { self.limit = limit }

    func register(_ task: URLSessionTask, continuation: CheckedContinuation<Result<Data, ComicImageFailure>, Never>) {
        lock.lock()
        transfers[task.taskIdentifier] = Transfer(continuation)
        lock.unlock()
    }

    private func transfer(for task: URLSessionTask) -> Transfer? {
        lock.lock()
        defer { lock.unlock() }
        return transfers[task.taskIdentifier]
    }

    private func complete(_ task: URLSessionTask, result: Result<Data, ComicImageFailure>) {
        lock.lock()
        let transfer = transfers.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        transfer?.continuation.resume(returning: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let failure = failure(for: response) {
            completionHandler(.cancel)
            complete(dataTask, result: .failure(failure))
        } else {
            completionHandler(.allow)
        }
    }

    private func failure(for response: URLResponse) -> ComicImageFailure? {
        guard let http = response as? HTTPURLResponse else { return .invalidResponse }
        guard (200..<300).contains(http.statusCode) else { return .http(http.statusCode) }
        return http.expectedContentLength > Int64(limit) ? .tooLarge : nil
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard let transfer = transfer(for: dataTask) else { return }
        guard chunk.count <= limit - transfer.bytes.count else {
            dataTask.cancel()
            complete(dataTask, result: .failure(.tooLarge))
            return
        }
        transfer.bytes.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let transfer = transfer(for: task) else { return }
        if let error {
            let failure: ComicImageFailure
            switch (error as? URLError)?.code {
            case .cancelled: failure = .cancelled
            case .timedOut: failure = .timedOut
            default: failure = .network
            }
            complete(task, result: .failure(failure))
        } else if transfer.bytes.isEmpty {
            complete(task, result: .failure(.emptyResponse))
        } else {
            complete(task, result: .success(transfer.bytes))
        }
    }
}
