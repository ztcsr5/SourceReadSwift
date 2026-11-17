import Darwin
import Foundation

/// A finite loopback HTTP peer that records the Cookie header actually received on the socket.
final class ComicCookieHTTPServer: @unchecked Sendable {
    private enum Failure: Error { case socket(String, Int32), invalidAddress }
    struct Request {
        let path: String
        let cookie: String?
    }

    static let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAIAAAASFvFNAAAAGklEQVR42mNgYGhg0ADiACBmCACygTggoAEAMGgE4bJ9Q/wAAAAASUVORK5CYII=")!
    let rootURL: URL
    let timeline = ComicCookieTimeline()
    private let listener: Int32
    private let responseCookie: String?
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "tests.comic-cookie-http")
    private let connections = DispatchQueue(label: "tests.comic-cookie-connections", attributes: .concurrent)
    private var clientSockets: Set<Int32> = []
    private var acceptedConnections = 0
    private var completedResponses = 0
    private var isStopped = false
    private var received: [Request] = []
    private var failure: String?

    init(responseCookieName: String? = nil) throws {
        let prefix = "/comic-cookie-" + UUID().uuidString.lowercased()
        let endpoint = try Self.openListener(prefix: prefix)
        listener = endpoint.socket
        rootURL = endpoint.url
        responseCookie = responseCookieName.map { "\($0)=response-session; Path=\(prefix); HttpOnly" }
    }

    func start() {
        timeline.record("server-start")
        queue.async { [self] in serveConnections() }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        isStopped = true
        for client in clientSockets { Darwin.shutdown(client, SHUT_RDWR) }
        Darwin.shutdown(listener, SHUT_RDWR)
    }

    func request(at url: URL) -> Request? {
        lock.lock()
        defer { lock.unlock() }
        return received.last { $0.path == url.path }
    }

    var serverFailure: String? {
        lock.lock()
        defer { lock.unlock() }
        return failure
    }

    var acceptedConnectionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return acceptedConnections
    }

    var diagnostics: String {
        lock.lock()
        defer { lock.unlock() }
        return "accepted=\(acceptedConnections) active=\(clientSockets.count) headers=\(received.count) responses=\(completedResponses) failure=\(failure ?? "none") events=[\(timeline.summary)]"
    }

    private static func openListener(prefix: String) throws -> (socket: Int32, url: URL) {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { throw Failure.socket("socket", errno) }
        var shouldClose = true
        defer { if shouldClose { Darwin.close(socket) } }
        var option: Int32 = 1
        Darwin.setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &option, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(socket, 8) == 0 else { throw Failure.socket("bind/listen", errno) }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.getsockname(socket, $0, &length) }
        }
        guard named == 0 else { throw Failure.socket("getsockname", errno) }
        guard let url = URL(string: "http://127.0.0.1:\(UInt16(bigEndian: address.sin_port))\(prefix)") else { throw Failure.invalidAddress }
        shouldClose = false
        return (socket, url)
    }

    private func serveConnections() {
        defer { Darwin.close(listener) }
        while true {
            let client = Darwin.accept(listener, nil, nil)
            lock.lock()
            if isStopped { lock.unlock(); if client >= 0 { Darwin.close(client) }; return }
            guard client >= 0 else { failure = "Loopback accept failed"; lock.unlock(); return }
            clientSockets.insert(client)
            acceptedConnections += 1
            let sequence = acceptedConnections
            timeline.record("accepted#\(sequence)")
            lock.unlock()
            // A preconnected socket may not send headers yet. It must not hold
            // the accept loop while a second connection has a complete request.
            connections.async { [self] in serveClient(client, sequence: sequence) }
        }
    }

    private func serveClient(_ client: Int32, sequence: Int) {
        timeline.record("serve#\(sequence)")
        defer {
            lock.lock()
            Darwin.close(client)
            clientSockets.remove(client)
            timeline.record("closed#\(sequence)")
            lock.unlock()
        }
        var option: Int32 = 1
        Darwin.setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &option, socklen_t(MemoryLayout<Int32>.size))
        if let request = readRequest(client) {
            timeline.record("headers#\(sequence)")
            lock.lock(); received.append(request); lock.unlock()
            sendImage(client, sequence: sequence)
        } else {
            timeline.record("no-headers#\(sequence)")
        }
    }

    private func readRequest(_ client: Int32) -> Request? {
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while bytes.count <= 16_384 {
            let count = Darwin.recv(client, &buffer, buffer.count, 0)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { return nil }
            bytes.append(buffer, count: count)
            guard bytes.range(of: Data("\r\n\r\n".utf8)) != nil else { continue }
            let lines = String(decoding: bytes, as: UTF8.self).components(separatedBy: "\r\n")
            guard let first = lines.first, let path = first.split(separator: " ").dropFirst().first else { return nil }
            let cookies = lines.dropFirst().compactMap { line -> String? in
                guard let colon = line.firstIndex(of: ":"), line[..<colon].lowercased() == "cookie" else { return nil }
                return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
            return Request(path: String(path), cookie: cookies.isEmpty ? nil : cookies.joined(separator: "; "))
        }
        lock.lock(); failure = "Loopback request exceeded 16 KiB"; lock.unlock()
        return nil
    }

    private func sendImage(_ client: Int32, sequence: Int) {
        let cookieField = responseCookie.map { "Set-Cookie: \($0)\r\n" } ?? ""
        var response = Data(("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: \(Self.image.count)\r\n"
            + cookieField + "Cache-Control: no-store\r\nConnection: close\r\n\r\n").utf8)
        response.append(Self.image)
        response.withUnsafeBytes { buffer in
            guard let address = buffer.baseAddress else { return }
            var sent = 0
            while sent < buffer.count {
                let count = Darwin.send(client, address.advanced(by: sent), buffer.count - sent, 0)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else {
                    let code = errno
                    lock.lock(); failure = "Loopback send failed, errno=\(code)"; lock.unlock()
                    return
                }
                sent += count
            }
            timeline.record("sent#\(sequence):bytes=\(sent)")
            lock.lock(); completedResponses += 1; lock.unlock()
        }
    }
}

/// Only fixed event labels and numeric transport facts belong in this bounded, monotonic trace.
final class ComicCookieTimeline: @unchecked Sendable {
    private let origin = ProcessInfo.processInfo.systemUptime
    private let lock = NSLock()
    private var events: [String] = []

    func record(_ event: String) {
        lock.lock()
        defer { lock.unlock() }
        guard events.count < 32 else { return }
        let milliseconds = Int((ProcessInfo.processInfo.systemUptime - origin) * 1_000)
        events.append("\(milliseconds)ms:\(event)")
    }

    var summary: String {
        lock.lock()
        defer { lock.unlock() }
        return events.joined(separator: ",")
    }
}
