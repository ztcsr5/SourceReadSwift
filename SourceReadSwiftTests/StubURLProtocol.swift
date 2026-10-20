import Foundation

/// URLProtocol stub for exercising the real `URLSessionSourceNetworkClient`
/// without network access. Register one handler per test and reset it in
/// `defer` so tests cannot leak responses into each other.
final class StubURLProtocol: URLProtocol {
    final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

        func set(_ handler: @escaping (URLRequest) -> (HTTPURLResponse, Data)) {
            lock.lock()
            defer { lock.unlock() }
            self.handler = handler
        }

        func reset() {
            lock.lock()
            defer { lock.unlock() }
            handler = nil
        }

        func response(for request: URLRequest) -> (HTTPURLResponse, Data)? {
            lock.lock()
            defer { lock.unlock() }
            return handler?(request)
        }
    }

    static let registry = Registry()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let (response, data) = Self.registry.response(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}