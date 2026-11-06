import XCTest
@testable import SourceReadSwift

/// Exercise production redirects through an isolated URLSession, never external hosts.
final class SourceRequestTransportTests: XCTestCase {
    private let cookieStore = SourceCookieStore(storageURL: nil)
    private let origin = "https://source.fixture.invalid/start"
    private let credentials = ["aUtHoRiZaTiOn": "Bearer fixture", "cookie": "sid=fixture",
                               "X-Source-Token": "fixture", "Accept": "text/html"]

    override func tearDown() {
        SourceTransportURLProtocol.registry.reset()
        super.tearDown()
    }

    func testCertificateFailureDoesNotRetryOverCleartext() async {
        SourceTransportURLProtocol.registry.configure([origin: .failure(.serverCertificateUntrusted)])
        let result = await load(origin, headers: credentials)
        guard case .failure = result else { return XCTFail("Invalid TLS must fail, got \(result)") }
        XCTAssertEqual(SourceTransportURLProtocol.registry.requests.map { $0.url?.scheme }, ["https"])
    }

    func testSameOriginRedirectRetainsExplicitCaseInsensitiveCookie() async throws {
        let target = "https://source.fixture.invalid/read"
        SourceTransportURLProtocol.registry.configure([
            origin: .http(302, ["Location": target], ""), target: .http(200, [:], "chapter")
        ])
        let jar = cookieStore
        await jar.storeSetCookieHeaders(["Set-Cookie": "jar=fixture; Path=/"], for: URL(string: origin)!)
        let response = try await load(origin, headers: credentials).get()
        XCTAssertEqual(response.body, "chapter")
        let request = try XCTUnwrap(SourceTransportURLProtocol.registry.requests.last)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "sid=fixture")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Source-Token"), "fixture")
    }

    func testCrossOriginHTTPAndHTMLRedirectsDiscardSourceCredentials() async throws {
        for target in ["https://other.fixture.invalid/read", "https://source.fixture.invalid:9443/read"] {
            for reply in [SourceTransportReply.http(302, ["Location": target], ""),
                          .http(200, [:], "<meta http-equiv='refresh' content='0;url=\(target)'>"),
                          .http(200, [:], "<script>location.href='\(target)'</script>")] {
                SourceTransportURLProtocol.registry.configure([origin: reply, target: .http(200, [:], "chapter")])
                let response = try await load(origin, headers: credentials).get()
                XCTAssertEqual(response.body, "chapter")
                let requests = SourceTransportURLProtocol.registry.requests
                XCTAssertEqual(requests.count, 2)
                let next = try XCTUnwrap(requests.last)
                for field in ["Authorization", "Cookie", "X-Source-Token"] {
                    XCTAssertNil(next.value(forHTTPHeaderField: field), "\(field) leaked to \(target)")
                }
                XCTAssertEqual(next.value(forHTTPHeaderField: "Accept"), "text/html")
            }
        }
    }

    func testRedirectCanUseOnlyTheDestinationCookieJar() async throws {
        let target = "https://other.fixture.invalid/read"
        let jar = cookieStore
        await jar.storeSetCookieHeaders(["Set-Cookie": "destination=fixture; Path=/; Secure"], for: URL(string: target)!)
        SourceTransportURLProtocol.registry.configure([
            origin: .http(302, ["Location": target], ""), target: .http(200, [:], "chapter")
        ])
        _ = try await load(origin, headers: credentials).get()
        let next = try XCTUnwrap(SourceTransportURLProtocol.registry.requests.last)
        XCTAssertEqual(next.value(forHTTPHeaderField: "Cookie"), "destination=fixture")
    }

    func testHTTPSDowngradeAndCredentialURLsAreRejectedBeforeSecondRequest() async {
        for target in ["http://source.fixture.invalid/read", "https://account:fixture@other.fixture.invalid/read"] {
            for reply in [SourceTransportReply.http(302, ["Location": target], ""),
                          .http(200, [:], "<script>location.href='\(target)'</script>")] {
                SourceTransportURLProtocol.registry.configure([origin: reply, target: .http(200, [:], "unexpected")])
                let result = await load(origin, headers: credentials)
                guard case .failure = result else { XCTFail("Unsafe redirect succeeded"); continue }
                XCTAssertEqual(SourceTransportURLProtocol.registry.requests.count, 1)
            }
        }
    }

    func testCrossOrigin307DoesNotReplayPostBody() async {
        let target = "https://other.fixture.invalid/read"
        SourceTransportURLProtocol.registry.configure([
            origin: .http(307, ["Location": target], ""), target: .http(200, [:], "unexpected")
        ])
        let result = await load(origin, method: .post, body: Data("account=fixture".utf8))
        guard case .failure = result else { return XCTFail("Cross-origin POST replay must fail") }
        XCTAssertEqual(SourceTransportURLProtocol.registry.requests.count, 1)
    }

    func testSameOrigin307PreservesPostAnd303ClearsContentHeaders() async throws {
        let target = "https://source.fixture.invalid/read"
        for code in [307, 303] {
            SourceTransportURLProtocol.registry.configure([
                origin: .http(code, ["Location": target], ""), target: .http(200, [:], "chapter")
            ])
            _ = try await load(origin, method: .post, headers: ["content-type": "application/x-www-form-urlencoded"],
                               body: Data("query=fixture".utf8)).get()
            let next = try XCTUnwrap(SourceTransportURLProtocol.registry.requests.last)
            XCTAssertEqual(next.httpMethod, code == 307 ? "POST" : "GET")
            if code == 303 { XCTAssertNil(next.value(forHTTPHeaderField: "Content-Type")) }
        }
    }

    func testEmbeddedURLInLoginQueryDoesNotReplaceRedirectDestination() async throws {
        let target = "https://source.fixture.invalid/login?next=https://other.fixture.invalid/read"
        SourceTransportURLProtocol.registry.configure([
            origin: .http(302, ["Location": target], ""), target: .http(200, [:], "login page")
        ])
        let response = try await load(origin, headers: credentials).get()
        XCTAssertEqual(response.url.absoluteString, target)
        XCTAssertEqual(response.body, "login page")
        XCTAssertEqual(SourceTransportURLProtocol.registry.requests.count, 2)
    }

    func testMalformedDoubleOriginCanStillBeRepairedWithoutLeakingCredentials() async throws {
        let target = "https://other.fixture.invalid/read"
        SourceTransportURLProtocol.registry.configure([
            origin: .http(302, ["Location": "https://source.fixture.invalid" + target], ""),
            target: .http(200, [:], "chapter")
        ])
        let response = try await load(origin, headers: credentials).get()
        XCTAssertEqual(response.url.absoluteString, target)
        let next = try XCTUnwrap(SourceTransportURLProtocol.registry.requests.last)
        XCTAssertNil(next.value(forHTTPHeaderField: "Authorization"))
    }

    func testDefaultHTTPSPortAndHeadKeepSameOriginSemantics() throws {
        let current = SourceRedirectRequest(url: URL(string: origin)!, method: .head, headers: credentials, body: nil)
        let next = try SourceRedirectPolicy.redirect(current, to: URL(string: "https://SOURCE.fixture.invalid:443/read")!, statusCode: 302)
        XCTAssertEqual(next.method, .head)
        XCTAssertEqual(next.headers["aUtHoRiZaTiOn"], "Bearer fixture")
        XCTAssertEqual(next.headers["cookie"], "sid=fixture")
    }

    func testHTTPAndHTMLRedirectChainsShareTheSameBoundedFailure() async {
        for usesHTML in [false, true] {
            var replies: [String: SourceTransportReply] = [:]
            for index in 0...10 {
                let next = "/r/\(index + 1)"
                replies["https://source.fixture.invalid/r/\(index)"] = usesHTML
                    ? .http(200, [:], "<script>location.href='\(next)'</script>")
                    : .http(302, ["Location": next], "")
            }
            SourceTransportURLProtocol.registry.configure(replies)
            let result = await load("https://source.fixture.invalid/r/0")
            guard case .failure = result else { XCTFail("Redirect limit must not return an interstitial as content"); continue }
            XCTAssertEqual(SourceTransportURLProtocol.registry.requests.count, 11)
        }
    }

    func testExplicitHTTPSourceRemainsSupported() async throws {
        let legacy = "http://legacy.fixture.invalid/read"
        SourceTransportURLProtocol.registry.configure([legacy: .http(200, [:], "legacy chapter")])
        let response = try await load(legacy).get()
        XCTAssertEqual(response.body, "legacy chapter")
    }

    private func load(_ address: String, method: SourceHTTPMethod = .get,
                      headers: [String: String] = [:], body: Data? = nil) async -> Result<SourceResponse, SourceEngineError> {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SourceTransportURLProtocol.self]
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = URLSessionSourceNetworkClient(session: session, cookieStore: cookieStore)
        return await client.load(SourceRequest(url: URL(string: address)!, method: method, headers: headers,
                                               body: body, expectedCharset: nil, timeout: 2))
    }
}

private enum SourceTransportReply {
    case http(Int, [String: String], String)
    case failure(URLError.Code)
}

private final class SourceTransportURLProtocol: URLProtocol {
    final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var replies: [String: SourceTransportReply] = [:]
        private var recorded: [URLRequest] = []

        var requests: [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        func configure(_ replies: [String: SourceTransportReply]) {
            lock.lock()
            defer { lock.unlock() }
            self.replies = replies
            recorded = []
        }

        func reset() { configure([:]) }

        func reply(for request: URLRequest) -> SourceTransportReply {
            lock.lock()
            defer { lock.unlock() }
            recorded.append(request)
            return replies[request.url?.absoluteString ?? ""] ?? .failure(.badURL)
        }
    }

    static let registry = Registry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        switch Self.registry.reply(for: request) {
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .http(let code, let headers, let body):
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
