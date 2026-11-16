import Darwin
import Foundation

/// Captures real loopback HTTP headers and answers bounded synthetic source requests.
final class ScriptHeaderHTTPFixture: @unchecked Sendable {
    struct Request {
        let path: String
        let headers: [String: String]
    }

    let baseURL: String
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "tests.script-header-http")
    private var listener: Int32
    private var client: Int32 = -1
    private var isStopped = false
    private var captured: [Request] = []

    init() throws {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { throw Self.failure("socket") }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(socket, 8) == 0 else {
            let failure = Self.failure("bind/listen"); Darwin.close(socket); throw failure
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.getsockname(socket, $0, &length) }
        }
        guard named == 0 else { let failure = Self.failure("getsockname"); Darwin.close(socket); throw failure }
        listener = socket
        baseURL = "http://127.0.0.1:\(UInt16(bigEndian: address.sin_port))"
        queue.async { [self] in serveRequests() }
    }

    var requests: [Request] {
        lock.lock(); defer { lock.unlock() }; return captured
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        isStopped = true
        if client >= 0 { Darwin.shutdown(client, SHUT_RDWR) }
        if listener >= 0 { Darwin.shutdown(listener, SHUT_RDWR) }
    }

    private func serveRequests() {
        defer {
            lock.lock(); Darwin.close(listener); listener = -1; lock.unlock()
        }
        while true {
            lock.lock(); let shouldStop = isStopped; lock.unlock()
            if shouldStop { return }
            let connection = Darwin.accept(listener, nil, nil)
            guard connection >= 0 else { return }
            lock.lock(); client = connection; let stopped = isStopped; lock.unlock()
            if !stopped { serve(connection) }
            lock.lock(); Darwin.close(connection); client = -1; lock.unlock()
        }
    }

    private func serve(_ connection: Int32) {
        var option: Int32 = 1
        Darwin.setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &option, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        Darwin.setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        guard let request = readRequest(connection) else { return }
        lock.lock(); captured.append(request); lock.unlock()
        let body = request.path.hasPrefix("/bootstrap") ? "synthetic-nonce"
            : #"{"books":[{"name":"Header fixture","url":"/book"}]}"#
        let response = Data(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
            + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body).utf8)
        response.withUnsafeBytes { buffer in
            guard let start = buffer.baseAddress else { return }
            var sent = 0
            while sent < buffer.count {
                let count = Darwin.send(connection, start.advanced(by: sent), buffer.count - sent, 0)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return }
                sent += count
            }
        }
    }

    private func readRequest(_ connection: Int32) -> Request? {
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while received.count <= 64 * 1024 {
            let count = Darwin.recv(connection, &buffer, buffer.count, 0)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { return nil }
            received.append(buffer, count: count)
            guard let boundary = received.range(of: Data("\r\n\r\n".utf8)) else { continue }
            let lines = String(decoding: received[..<boundary.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
            let requestLine = lines[0].split(separator: " ")
            guard requestLine.count >= 2 else { return nil }
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard pair.count == 2 else { continue }
                headers[String(pair[0]).lowercased()] = pair[1].trimmingCharacters(in: .whitespaces)
            }
            return Request(path: String(requestLine[1]), headers: headers)
        }
        return nil
    }

    private static func failure(_ operation: String) -> NSError {
        NSError(domain: "ScriptHeaderHTTPFixture", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: operation + " failed"])
    }
}
