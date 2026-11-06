import Foundation

/// WebSocket abstraction so the protocol loop can be tested with a fake.
protocol CloudTTSWebSocket: AnyObject {
    func resume()
    func send(_ data: Data, completion: @escaping (Error?) -> Void)
    func receive(completion: @escaping (Result<Data, Error>) -> Void)
    func cancel()
}

protocol CloudTTSWebSocketFactory {
    func makeWebSocket(url: URL) -> CloudTTSWebSocket
}

final class URLSessionCloudTTSWebSocket: CloudTTSWebSocket {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func resume() {
        task.resume()
    }

    func send(_ data: Data, completion: @escaping (Error?) -> Void) {
        task.send(.data(data)) { error in
            completion(error)
        }
    }

    func receive(completion: @escaping (Result<Data, Error>) -> Void) {
        task.receive { result in
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    completion(.success(data))
                case .string(let text):
                    completion(.success(Data(text.utf8)))
                @unknown default:
                    completion(.failure(XunfeiTTSError.invalidFrame))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func cancel() {
        task.cancel(with: .goingAway, reason: nil)
    }
}

struct URLSessionCloudTTSWebSocketFactory: CloudTTSWebSocketFactory {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func makeWebSocket(url: URL) -> CloudTTSWebSocket {
        URLSessionCloudTTSWebSocket(task: session.webSocketTask(with: url))
    }
}

/// Runs the full iFlyTek TTS v2 handshake and accumulates the returned MP3 data.
final class CloudTTSClient {
    private let factory: CloudTTSWebSocketFactory
    private let timeout: TimeInterval

    init(
        factory: CloudTTSWebSocketFactory = URLSessionCloudTTSWebSocketFactory(),
        timeout: TimeInterval = 30
    ) {
        self.factory = factory
        self.timeout = timeout.isFinite && timeout > 0 ? timeout : 30
    }

    func synthesize(text: String, credentials: CloudTTSCredentials) async throws -> Data {
        guard credentials.isConfigured else { throw XunfeiTTSError.notConfigured }
        let config = credentials.protocolConfig
        guard let url = CloudTTSProtocol.createXunfeiAuthURL(config: config),
              let payload = CloudTTSProtocol.createSynthesisPayload(text: text, config: config) else {
            throw XunfeiTTSError.invalidResponse
        }
        return try await run(url: url, payload: payload)
    }

    private func run(url: URL, payload: Data) async throws -> Data {
        try Task.checkCancellation()
        let socket = factory.makeWebSocket(url: url)
        defer { socket.cancel() }
        socket.resume()

        try await send(payload, on: socket)

        var audio = Data()
        while true {
            try Task.checkCancellation()
            let frameData = try await receive(on: socket)
            let frame = try XunfeiTTSFrame.decode(frameData)
            if frame.code != 0 {
                throw XunfeiTTSError.server(code: frame.code, message: frame.message ?? "unknown")
            }
            if let chunk = frame.decodedAudio {
                audio.append(chunk)
            }
            if frame.isFinal { break }
        }
        guard !audio.isEmpty else { throw XunfeiTTSError.emptyAudio }
        return audio
    }

    private func send(_ data: Data, on socket: CloudTTSWebSocket) async throws {
        let _: Void = try await awaitCallback(on: socket) { finish in
            socket.send(data) { error in
                if let error {
                    finish(.failure(error))
                } else {
                    finish(.success(Void()))
                }
            }
        }
    }

    private func receive(on socket: CloudTTSWebSocket) async throws -> Data {
        try await awaitCallback(on: socket) { finish in
            socket.receive(completion: finish)
        }
    }

    private func awaitCallback<T>(on socket: CloudTTSWebSocket,
                                  start: (@escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
        let operation = TTSCallbackOperation<T>()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                guard operation.install(continuation) else { return }
                operation.armTimeout(seconds: timeout)
                start { operation.finish($0) }
            }
        }, onCancel: {
            operation.finish(.failure(CancellationError()))
            socket.cancel()
        })
    }
}

/// Socket callbacks can outlive cancellation. Complete the caller once without waiting for them.
private final class TTSCallbackOperation<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var outcome: Result<Value, Error>?
    private var timer: DispatchWorkItem?

    func install(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        if let outcome {
            lock.unlock()
            continuation.resume(with: outcome)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func armTimeout(seconds: TimeInterval) {
        let timeout = DispatchWorkItem { [weak self] in self?.finish(.failure(XunfeiTTSError.timeout)) }
        lock.lock()
        guard outcome == nil else { lock.unlock(); return }
        timer = timeout
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds, execute: timeout)
    }

    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard outcome == nil else { lock.unlock(); return }
        outcome = result
        let pending = continuation
        continuation = nil
        let timeout = timer
        timer = nil
        lock.unlock()
        timeout?.cancel()
        pending?.resume(with: result)
    }
}
