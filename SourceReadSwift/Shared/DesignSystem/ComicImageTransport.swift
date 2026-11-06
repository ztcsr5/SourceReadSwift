import Foundation

/// Reads comic responses in URLSession chunks so rejected bodies never reach image decoding.
final class ComicImageTransport: Sendable {
    private let session: URLSession
    private let receiver: ComicImageReceiver

    init(configuration: URLSessionConfiguration) {
        guard let transportConfiguration = configuration.copy() as? URLSessionConfiguration else {
            preconditionFailure("URLSessionConfiguration must produce a configuration copy")
        }
        transportConfiguration.protocolClasses = configuration.protocolClasses
        var headers = transportConfiguration.httpAdditionalHeaders as? [String: String] ?? [String: String]()
        headers["Accept-Encoding"] = "identity"
        transportConfiguration.httpAdditionalHeaders = headers
        let receiver = ComicImageReceiver(limit: ComicOfflineArchive.maximumPageBytes)
        self.receiver = receiver
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        self.session = URLSession(configuration: transportConfiguration, delegate: receiver, delegateQueue: delegateQueue)
    }

    deinit { session.invalidateAndCancel() }

    func load(_ request: URLRequest) async -> Result<Data, ComicImageFailure> {
        guard !Task.isCancelled else { return .failure(.cancelled) }
        var mutableRequest = request
        if mutableRequest.value(forHTTPHeaderField: "Accept-Encoding") == nil {
            mutableRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        }
        let cancellation = ComicTransferCancellation()
        let result: Result<Data, ComicImageFailure> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let task = session.dataTask(with: mutableRequest)
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
final class ComicImageReceiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
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
        print("[DIAG-RECEIVER] complete task=\(task.taskIdentifier) transferPresent=\(transfer != nil) result=\(result)")
        transfer?.continuation.resume(returning: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        print("[DIAG-RECEIVER] didReceiveResponse url=\(response.url?.absoluteString ?? "") status=\((response as? HTTPURLResponse)?.statusCode ?? -1) expected=\(response.expectedContentLength)")
        if let failure = ComicImageResponsePolicy.failure(for: response,
                                                           expectedBodyBytes: dataTask.countOfBytesExpectedToReceive,
                                                           limit: limit) {
            print("[DIAG-RECEIVER] failure=\(failure)")
            // Commit the application rejection before cancellation can re-enter
            // didCompleteWithError and replace it with a transport error.
            complete(dataTask, result: .failure(failure))
            completionHandler(.cancel)
        } else {
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        print("[DIAG-RECEIVER] didReceiveChunk bytes=\(chunk.count)")
        guard let transfer = transfer(for: dataTask) else { return }
        guard chunk.count <= limit - transfer.bytes.count else {
            print("[DIAG-RECEIVER] chunk exceeded limit, completing tooLarge")
            complete(dataTask, result: .failure(.tooLarge))
            dataTask.cancel()
            return
        }
        transfer.bytes.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        for metric in metrics.transactionMetrics {
            let proto = metric.networkProtocolName ?? "unknown"
            print("[DIAG-RECEIVER] metrics requestStart=\(String(describing: metric.requestStartDate)) responseStart=\(String(describing: metric.responseStartDate)) responseEnd=\(String(describing: metric.responseEndDate)) protocol=\(proto)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        print("[DIAG-RECEIVER] didCompleteWithError error=\(String(describing: error))")
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

/// A protocol adapter can supply Content-Length without populating expectedContentLength.
enum ComicImageResponsePolicy {
    static func failure(for response: URLResponse, expectedBodyBytes: Int64 = -1, limit: Int) -> ComicImageFailure? {
        guard let http = response as? HTTPURLResponse else { return .invalidResponse }
        guard (200..<300).contains(http.statusCode) else { return .http(http.statusCode) }
        if max(response.expectedContentLength, expectedBodyBytes) > Int64(limit) { return .tooLarge }
        if let declared = http.value(forHTTPHeaderField: "Content-Length") {
            let text = declared.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return .invalidResponse }
            guard let count = Int64(text) else { return .tooLarge }
            if count > Int64(limit) { return .tooLarge }
        }
        return nil
    }
}
