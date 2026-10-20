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
        self.timeout = timeout
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
        let socket = factory.makeWebSocket(url: url)
        defer { socket.cancel() }
        socket.resume()

        try await withTimeout { try await self.send(payload, on: socket) }

        var audio = Data()
        while true {
            let frameData = try await withTimeout { try await self.receive(on: socket) }
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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.send(data) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func receive(on socket: CloudTTSWebSocket) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            socket.receive { result in
                continuation.resume(with: result)
            }
        }
    }

    private func withTimeout<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.timeout * 1_000_000_000))
                throw XunfeiTTSError.timeout
            }
            guard let result = try await group.next() else {
                throw XunfeiTTSError.timeout
            }
            group.cancelAll()
            return result
        }
    }
}
