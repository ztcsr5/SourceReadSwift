import Foundation
#if canImport(Darwin)
import Darwin
#endif
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

    private let lock = NSLock()
    private let mode: Mode
    private var observation = Observation()
    private var serverSocket: Int32 = -1
    private var clientSocket: Int32 = -1
    private var running = false
    private let queue = DispatchQueue(label: "tests.comic-held-http", qos: .userInitiated)
    private static let chunkBytes = 1024 * 1024
    private lazy var chunkFrame: Data = {
        var frame = Data("100000\r\n".utf8)
        frame.append(Data(repeating: 0, count: Self.chunkBytes))
        frame.append(Data("\r\n".utf8))
        return frame
    }()

    init(mode: Mode) throws {
        self.mode = mode
    }

    var snapshot: Observation {
        lock.lock()
        defer { lock.unlock() }
        return observation
    }

    func start() {
        queue.async { [weak self] in
            self?.runServer()
        }
    }

    func stop() {
        lock.lock()
        running = false
        let sSock = serverSocket
        let cSock = clientSocket
        serverSocket = -1
        clientSocket = -1
        lock.unlock()

        #if canImport(Darwin)
        if cSock >= 0 {
            Darwin.close(cSock)
        }
        if sSock >= 0 {
            Darwin.close(sSock)
        }
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
        guard fd >= 0 else {
            let err = errno
            print("[DIAG-SERVER] socket() failed errno=\(err)")
            updateObservation { $0.failure = "socket() failed: \(err)" }
            return
        }

        var opt: Int32 = 1
        Darwin.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
        Darwin.setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let err = errno
            Darwin.close(fd)
            print("[DIAG-SERVER] bind() failed errno=\(err)")
            updateObservation { $0.failure = "bind() failed: \(err)" }
            return
        }

        guard Darwin.listen(fd, 5) == 0 else {
            let err = errno
            Darwin.close(fd)
            print("[DIAG-SERVER] listen() failed errno=\(err)")
            updateObservation { $0.failure = "listen() failed: \(err)" }
            return
        }

        var assignedAddr = sockaddr_in()
        var assignedLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &assignedAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.getsockname(fd, sa, &assignedLen)
            }
        }
        guard nameResult == 0 else {
            let err = errno
            Darwin.close(fd)
            print("[DIAG-SERVER] getsockname() failed errno=\(err)")
            updateObservation { $0.failure = "getsockname() failed: \(err)" }
            return
        }

        let port = UInt16(bigEndian: assignedAddr.sin_port)
        guard let url = URL(string: "http://127.0.0.1:\(port)/page") else {
            Darwin.close(fd)
            print("[DIAG-SERVER] URL construction failed for port \(port)")
            updateObservation { $0.failure = "URL construction failed" }
            return
        }

        lock.lock()
        serverSocket = fd
        running = true
        lock.unlock()

        print("[DIAG-SERVER] Listening on \(url)")
        updateObservation { $0.address = url }

        let client = Darwin.accept(fd, nil, nil)
        guard client >= 0 else {
            print("[DIAG-SERVER] accept() returned \(client) errno=\(errno)")
            return
        }

        Darwin.setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen_t(MemoryLayout<Int32>.size))

        lock.lock()
        clientSocket = client
        lock.unlock()

        print("[DIAG-SERVER] Client accepted fd=\(client)")
        handleClient(client)
        #endif
    }

    #if canImport(Darwin)
    private func handleClient(_ client: Int32) {
        var accumulated = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = Darwin.recv(client, &buffer, buffer.count, 0)
            if bytesRead <= 0 {
                print("[DIAG-SERVER] recv returned \(bytesRead) errno=\(errno) before full headers")
                updateObservation { $0.failure = "Client closed before headers" }
                return
            }
            accumulated.append(buffer, count: bytesRead)
            if accumulated.range(of: Data("\r\n\r\n".utf8)) != nil {
                break
            }
            if accumulated.count > 16384 {
                print("[DIAG-SERVER] Headers exceeded 16 KiB")
                updateObservation { $0.failure = "Request headers exceeded 16 KiB" }
                return
            }
        }

        print("[DIAG-SERVER] Received request (\(accumulated.count) bytes)")

        let framing = mode == .declared
            ? "Content-Length: \(ComicOfflineArchive.maximumPageBytes + 1)\r\n"
            : "Transfer-Encoding: chunked\r\n"
        let headerStr = "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\n" + framing + "Connection: keep-alive\r\n\r\n"
        let headerData = Data(headerStr.utf8)
        let sentHeaderBytes = headerData.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return -1 }
            return Darwin.send(client, base, headerData.count, 0)
        }
        guard sentHeaderBytes == headerData.count else {
            print("[DIAG-SERVER] send() header failed sent=\(sentHeaderBytes) expected=\(headerData.count) errno=\(errno)")
            updateObservation { $0.failure = "Failed to send response headers" }
            return
        }
        updateObservation { $0.sentHeaders = true }
        print("[DIAG-SERVER] Sent response headers successfully (\(sentHeaderBytes) bytes)")

        if mode == .chunked {
            let chunks = ComicOfflineArchive.maximumPageBytes / Self.chunkBytes + 1
            for i in 0..<chunks {
                let sent = chunkFrame.withUnsafeBytes { ptr -> Int in
                    guard let base = ptr.baseAddress else { return -1 }
                    return Darwin.send(client, base, chunkFrame.count, 0)
                }
                print("[DIAG-SERVER] Sent chunk \(i+1)/\(chunks) sentBytes=\(sent)")
                if sent <= 0 {
                    break
                }
                updateObservation { $0.sentBodyBytes += Self.chunkBytes }
            }
        }

        print("[DIAG-SERVER] Waiting for peer closure...")
        var discard = [UInt8](repeating: 0, count: 256)
        while true {
            let ret = Darwin.recv(client, &discard, discard.count, 0)
            if ret <= 0 {
                print("[DIAG-SERVER] Peer closed fd=\(client) ret=\(ret) errno=\(errno)")
                updateObservation { $0.peerClosed = true }
                break
            }
        }
    }
    #endif
}
