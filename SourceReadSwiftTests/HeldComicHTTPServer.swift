import Foundation
import Network
@testable import SourceReadSwift

/// A loopback-only HTTP peer that withholds EOF until the reader cancels it.
final class HeldComicHTTPServer: @unchecked Sendable {
    enum Mode: CaseIterable, Equatable { case declared, chunked }
    struct Observation {
        var address: URL?
        var failure: String?
        var sentHeaders = false
        var sentBodyBytes = 0
        var peerClosed = false
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "tests.comic-held-http")
    private let lock = NSLock()
    private let mode: Mode
    private var connections: [NWConnection] = []
    private var observation = Observation()
    private static let chunkBytes = 1024 * 1024
    private lazy var chunkFrame: Data = {
        var frame = Data("100000\r\n".utf8)
        frame.append(Data(repeating: 0, count: Self.chunkBytes))
        frame.append(Data("\r\n".utf8))
        return frame
    }()

    init(mode: Mode) throws {
        self.mode = mode
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    var snapshot: Observation {
        lock.lock()
        defer { lock.unlock() }
        return observation
    }

    func start() {
        listener.stateUpdateHandler = { [weak self] state in self?.recordListenerState(state) }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            self.readRequest(connection, accumulated: Data())
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener.cancel()
        queue.sync {
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    private func updateObservation(_ update: (inout Observation) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        update(&observation)
    }

    private func recordListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener.port,
                  let address = URL(string: "http://127.0.0.1:\(port.rawValue)/page") else {
                updateObservation { $0.failure = "Loopback listener has no assigned port" }
                return
            }
            updateObservation { $0.address = address }
        case .failed(let error): updateObservation { $0.failure = error.localizedDescription }
        default: break
        }
    }

    private func readRequest(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self, weak connection] bytes, _, isComplete, error in
            guard let self, let connection else { return }
            var request = accumulated
            if let bytes { request.append(bytes) }
            guard request.count <= 16 * 1024 else {
                self.updateObservation { $0.failure = "Test HTTP request exceeded 16 KiB" }
                connection.cancel()
                return
            }
            if request.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.sendResponse(connection)
            } else if let error {
                self.updateObservation { $0.failure = error.localizedDescription }
                connection.cancel()
            } else if isComplete {
                self.updateObservation { $0.failure = "Test client closed before request headers" }
                connection.cancel()
            } else {
                self.readRequest(connection, accumulated: request)
            }
        }
    }

    private func sendResponse(_ connection: NWConnection) {
        let framing = mode == .declared
            ? "Content-Length: \(ComicOfflineArchive.maximumPageBytes + 1)\r\n"
            : "Transfer-Encoding: chunked\r\n"
        let header = Data(("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\n" + framing + "Connection: keep-alive\r\n\r\n").utf8)
        connection.send(content: header, completion: .contentProcessed { [weak self, weak connection] error in
            guard let self, let connection else { return }
            guard error == nil else {
                self.updateObservation { $0.failure = "Failed to send loopback response headers" }
                connection.cancel()
                return
            }
            self.updateObservation { $0.sentHeaders = true }
            if self.mode == .declared {
                // Send no body and no FIN: only a header-phase rejection can pass.
                self.observePeerClosure(connection)
            } else {
                let chunks = ComicOfflineArchive.maximumPageBytes / Self.chunkBytes + 1
                self.sendChunk(connection, remaining: chunks)
            }
        })
    }

    private func sendChunk(_ connection: NWConnection, remaining: Int) {
        guard remaining > 0 else {
            // Deliberately omit the terminating zero chunk and FIN.
            observePeerClosure(connection)
            return
        }
        connection.send(content: chunkFrame, completion: .contentProcessed { [weak self, weak connection] error in
            guard let self, let connection else { return }
            if error != nil {
                self.updateObservation { $0.peerClosed = true }
                return
            }
            self.updateObservation { $0.sentBodyBytes += Self.chunkBytes }
            self.sendChunk(connection, remaining: remaining - 1)
        })
    }

    private func observePeerClosure(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self, weak connection] _, _, isComplete, error in
            guard let self, let connection else { return }
            if isComplete || error != nil {
                self.updateObservation { $0.peerClosed = true }
            } else {
                self.observePeerClosure(connection)
            }
        }
    }
}
