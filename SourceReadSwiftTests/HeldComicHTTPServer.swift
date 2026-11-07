import Foundation
#if canImport(Darwin)
import Darwin
#endif
@testable import SourceReadSwift

/// A loopback HTTP peer that withholds EOF until the reader cancels it.
final class HeldComicHTTPServer: @unchecked Sendable {
    enum Mode: CaseIterable, Equatable { case declared, declaredPrefix, chunked }
    struct Observation {
        var address: URL?
        var failure: String?
        var acceptedClient = false
        var receivedRequestHeaders = false
        var sentHeaders = false
        var sentHeaderBytes = 0
        var sentBodyBytes = 0
        var peerClosed = false
    }

    private let lock = NSLock()
    private let mode: Mode
    private var observation = Observation()
    private var serverSocket: Int32 = -1
    private var clientSocket: Int32 = -1
    private var hasStarted = false
    private var isStopped = false
    private let queue = DispatchQueue(label: "tests.comic-held-http", qos: .userInitiated)
    private static let chunkBytes = 1024 * 1024
    private static let chunkPrefix = Data("100000\r\n".utf8)
    private lazy var chunkFrame: Data = {
        var frame = Self.chunkPrefix
        frame.append(Data(repeating: 0, count: Self.chunkBytes))
        frame.append(Data("\r\n".utf8))
        return frame
    }()

    init(mode: Mode) throws { self.mode = mode }

    var snapshot: Observation {
        lock.lock()
        defer { lock.unlock() }
        return observation
    }

    func start() {
        lock.lock()
        guard !hasStarted, !isStopped else { lock.unlock(); return }
        hasStarted = true
        lock.unlock()
        queue.async { [weak self] in self?.runServer() }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        isStopped = true
        #if canImport(Darwin)
        // The worker owns close(). Shutdown wakes blocked accept/recv/send,
        // without another thread closing and then reusing its descriptor.
        if clientSocket >= 0 { Darwin.shutdown(clientSocket, SHUT_RDWR) }
        if serverSocket >= 0 { Darwin.shutdown(serverSocket, SHUT_RDWR) }
        #endif
    }

    private func updateObservation(_ update: (inout Observation) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        update(&observation)
    }

    private func runServer() {
        #if canImport(Darwin)
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { recordFailure("socket", code: errno); return }
        lock.lock()
        guard !isStopped else { lock.unlock(); Darwin.close(fd); return }
        serverSocket = fd
        lock.unlock()
        defer { closeSockets() }

        var option: Int32 = 1
        Darwin.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &option, socklen_t(MemoryLayout<Int32>.size))
        Darwin.setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &option, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { recordFailure("bind", code: errno); return }
        guard Darwin.listen(fd, 1) == 0 else { recordFailure("listen", code: errno); return }
        lock.lock()
        let stoppedBeforeAccept = isStopped
        lock.unlock()
        guard !stoppedBeforeAccept else { return }
        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &assigned) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.getsockname(fd, $0, &length) }
        }
        guard named == 0 else { recordFailure("getsockname", code: errno); return }
        let port = UInt16(bigEndian: assigned.sin_port)
        guard let url = URL(string: "http://127.0.0.1:\(port)/page") else {
            updateObservation { $0.failure = "Invalid loopback URL" }; return
        }
        updateObservation { $0.address = url }
        let client = Darwin.accept(fd, nil, nil)
        guard client >= 0 else { recordFailure("accept", code: errno); return }
        lock.lock()
        guard !isStopped else { lock.unlock(); Darwin.close(client); return }
        clientSocket = client
        observation.acceptedClient = true
        lock.unlock()
        Darwin.setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &option, socklen_t(MemoryLayout<Int32>.size))
        Darwin.setsockopt(client, IPPROTO_TCP, TCP_NODELAY, &option, socklen_t(MemoryLayout<Int32>.size))
        serve(client)
        #endif
    }

    #if canImport(Darwin)
    private func recordFailure(_ operation: String, code: Int32) {
        updateObservation { $0.failure = "\(operation) failed, errno=\(code)" }
    }

    private func closeSockets() {
        lock.lock()
        defer { lock.unlock() }
        if clientSocket >= 0 { Darwin.close(clientSocket); clientSocket = -1 }
        if serverSocket >= 0 { Darwin.close(serverSocket); serverSocket = -1 }
    }

    private func readRequest(_ client: Int32) -> Bool {
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while received.count <= 16_384 {
            let count = Darwin.recv(client, &buffer, buffer.count, 0)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { recordFailure("recv request", code: errno); return false }
            received.append(buffer, count: count)
            if received.range(of: Data("\r\n\r\n".utf8)) != nil {
                updateObservation { $0.receivedRequestHeaders = true }
                return true
            }
        }
        updateObservation { $0.failure = "Request headers exceeded 16 KiB" }
        return false
    }

    private func serve(_ client: Int32) {
        guard readRequest(client) else { return }
        let framing = mode == .chunked ? "Transfer-Encoding: chunked\r\n"
            : "Content-Length: \(ComicOfflineArchive.maximumPageBytes + 1)\r\n"
        let headers = Data(("HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n"
                            + framing + "Connection: close\r\n\r\n").utf8)
        let headerCount = sendAll(headers, client: client, bodyRange: nil)
        updateObservation { $0.sentHeaderBytes = headerCount; $0.sentHeaders = headerCount == headers.count }
        guard headerCount == headers.count else { recordFailure("send headers", code: errno); return }
        if mode == .declaredPrefix {
            _ = sendAll(Data([0]), client: client, bodyRange: 0..<1)
        } else if mode == .chunked {
            let payloadRange = Self.chunkPrefix.count..<(Self.chunkPrefix.count + Self.chunkBytes)
            let chunks = ComicOfflineArchive.maximumPageBytes / Self.chunkBytes + 1
            for _ in 0..<chunks {
                if sendAll(chunkFrame, client: client, bodyRange: payloadRange) != chunkFrame.count { break }
            }
        }
        // .declared sends exactly zero bytes after the header terminator.
        var discard = [UInt8](repeating: 0, count: 256)
        while true {
            let count = Darwin.recv(client, &discard, discard.count, 0)
            let receiveError = errno
            if count < 0, receiveError == EINTR { continue }
            if count <= 0 {
                lock.lock()
                observation.peerClosed = !isStopped && (count == 0 || receiveError == ECONNRESET)
                lock.unlock()
                return
            }
        }
    }

    private func sendAll(_ bytes: Data, client: Int32, bodyRange: Range<Int>?) -> Int {
        var offset = 0
        bytes.withUnsafeBytes { buffer in
            guard let pointer = buffer.baseAddress else { return }
            while offset < bytes.count {
                let count = Darwin.send(client, pointer.advanced(by: offset), bytes.count - offset, 0)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return }
                if let bodyRange {
                    let payloadCount = max(0, min(offset + count, bodyRange.upperBound) - max(offset, bodyRange.lowerBound))
                    updateObservation { $0.sentBodyBytes += payloadCount }
                }
                offset += count
            }
        }
        return offset
    }
    #endif
}

/// Independent Foundation control, using the same held-open HTTP response.
final class HeldComicResponseProbe: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var receivedResponse = false
    private var completedErrorCode: Int?
    private var session: URLSession?
    private var task: URLSessionDataTask?

    func start(url: URL, configuration: URLSessionConfiguration) {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        let task = session.dataTask(with: url)
        self.task = task
        task.resume()
    }

    func stop() { session?.invalidateAndCancel(); session = nil }

    var summary: String {
        lock.lock()
        defer { lock.unlock() }
        return "responseCallback=\(receivedResponse) taskResponse=\(task?.response != nil) expectedBytes=\(task?.countOfBytesExpectedToReceive ?? -1) responseExpectedBytes=\(task?.response?.expectedContentLength ?? -1) errorCode=\(completedErrorCode.map(String.init) ?? "none")"
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock(); receivedResponse = true; lock.unlock()
        completionHandler(.cancel)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); completedErrorCode = (error as NSError?)?.code; lock.unlock()
    }
}
