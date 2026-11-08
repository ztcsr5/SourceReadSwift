import Foundation

/// Reads comic responses in URLSession chunks so rejected bodies never reach image decoding.
final class ComicImageTransport: Sendable {
    private let session: URLSession
    private let receiver: ComicImageReceiver
    private let requestTimeout: TimeInterval
    private let resourceTimeout: TimeInterval

    init(configuration: URLSessionConfiguration) {
        guard let transportConfiguration = configuration.copy() as? URLSessionConfiguration else {
            preconditionFailure("URLSessionConfiguration must produce a configuration copy")
        }
        transportConfiguration.protocolClasses = configuration.protocolClasses
        let requestTimeout = ComicImageTimeoutPolicy.valid(configuration.timeoutIntervalForRequest,
                                                           fallback: ComicImageTimeoutPolicy.defaultRequest)
        let resourceTimeout = ComicImageTimeoutPolicy.valid(configuration.timeoutIntervalForResource,
                                                            fallback: ComicImageTimeoutPolicy.defaultResource)
        transportConfiguration.timeoutIntervalForRequest = requestTimeout
        transportConfiguration.timeoutIntervalForResource = resourceTimeout
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
        transportConfiguration.urlCache = nil
        transportConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
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
        // URLRequest's explicit timeout otherwise overrides a shorter injected
        // session timeout, leaving invisible headers waiting for the full 18s.
        mutableRequest.timeoutInterval = ComicImageTimeoutPolicy.effectiveRequest(
            requested: request.timeoutInterval, configured: requestTimeout, resource: resourceTimeout)
        mutableRequest.cachePolicy = .reloadIgnoringLocalCacheData
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

/// Keep finite request/resource bounds without inventing a response before CFNetwork delivers one.
enum ComicImageTimeoutPolicy {
    static let defaultRequest: TimeInterval = 18
    static let defaultResource: TimeInterval = 30

    static func valid(_ interval: TimeInterval, fallback: TimeInterval) -> TimeInterval {
        interval.isFinite && interval > 0 ? interval : fallback
    }

    static func effectiveRequest(requested: TimeInterval, configured: TimeInterval, resource: TimeInterval) -> TimeInterval {
        min(valid(requested, fallback: defaultRequest),
            valid(configured, fallback: defaultRequest),
            valid(resource, fallback: defaultResource))
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
        trace("complete task=\(task.taskIdentifier) transferPresent=\(transfer != nil)")
        transfer?.continuation.resume(returning: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        trace("response task=\(dataTask.taskIdentifier) status=\((response as? HTTPURLResponse)?.statusCode ?? -1) expected=\(response.expectedContentLength)")
        if let failure = ComicImageResponsePolicy.failure(for: response,
                                                           expectedBodyBytes: dataTask.countOfBytesExpectedToReceive,
                                                           limit: limit) {
            trace("rejected task=\(dataTask.taskIdentifier) failure=\(failure)")
            // Commit the application rejection before cancellation can re-enter
            // didCompleteWithError and replace it with a transport error.
            complete(dataTask, result: .failure(failure))
            completionHandler(.cancel)
        } else {
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        trace("chunk task=\(dataTask.taskIdentifier) bytes=\(chunk.count)")
        guard let transfer = transfer(for: dataTask) else { return }
        guard chunk.count <= limit - transfer.bytes.count else {
            trace("chunk exceeded limit task=\(dataTask.taskIdentifier)")
            complete(dataTask, result: .failure(.tooLarge))
            dataTask.cancel()
            return
        }
        transfer.bytes.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        for metric in metrics.transactionMetrics {
            let proto = metric.networkProtocolName ?? "unknown"
            trace("metrics task=\(task.taskIdentifier) responseStarted=\(metric.responseStartDate != nil) responseEnded=\(metric.responseEndDate != nil) protocol=\(proto)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        trace("finished task=\(task.taskIdentifier) errorCode=\((error as NSError?)?.code ?? 0)")
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

    private func trace(_ event: @autoclosure () -> String) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SOURCE_READ_COMIC_DIAGNOSTICS"] == "1" {
            print("[DIAG-RECEIVER] \(event())")
        }
        #endif
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
