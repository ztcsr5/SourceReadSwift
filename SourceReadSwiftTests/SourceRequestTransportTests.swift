import XCTest
@testable import SourceReadSwift

/// Exercise production requests and redirects through an isolated URLSession, never external hosts.
final class SourceRequestTransportTests: XCTestCase {
    private let cookieStore = SourceCookieStore(storageURL: nil)
    private let origin = "https://source.fixture.invalid/start"
    private let credentials = ["aUtHoRiZaTiOn": "Bearer fixture", "cookie": "sid=fixture",
                               "X-Source-Token": "fixture", "Accept": "text/html"]

    override func tearDown() {
        SourceTransportURLProtocol.registry.reset()
        super.tearDown()
    }

    func testDefaultObjectBodiesReachTransportAsTypedJSON() async throws {
        let body = #"{"q":"a&b","page":2,"enabled":true,"filter":{"label":"小说"},"tags":["one","two"]}"#
        let source = BookSource(bookSourceName: "Object fixture", bookSourceUrl: origin)
        let configured = BookSource(bookSourceName: "Configured object fixture", bookSourceUrl: origin,
                                    customConfig: #"{"body":\#(body)}"#)
        let requests = [
            SourceRequestBuilder().buildPageRequest(source: source, urlText: origin + #",{"body":\#(body)}"#),
            SourceRequestBuilder().buildPageRequest(source: configured, urlText: origin)
        ]
        for request in requests {
            SourceTransportURLProtocol.registry.configure([origin: .http(200, [:], "accepted")])
            _ = try await load(request).get()
            let sent = try XCTUnwrap(SourceTransportURLProtocol.registry.requests.first)
            XCTAssertEqual(sent.httpMethod, "POST")
            XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: readBody(sent)) as? [String: Any])
            XCTAssertEqual(object["q"] as? String, "a&b")
            XCTAssertEqual(object["page"] as? Int, 2)
            XCTAssertEqual(object["enabled"] as? Bool, true)
            XCTAssertEqual(object["filter"] as? [String: String], ["label": "小说"])
            XCTAssertEqual(object["tags"] as? [String], ["one", "two"])
        }
    }

    func testObjectBodyUsesFinalCaseInsensitiveFormHeader() async throws {
        let bodyOption = #",{"body":{"a":"1&2","b":"2"}}"#
        let form = "application/x-www-form-urlencoded; charset=UTF-8"
        let fixtures: [(BookSource, String, [String: String])] = [
            (BookSource(bookSourceName: "Source header", bookSourceUrl: origin,
                        header: #"{"content-type":"\#(form)"}"#), bodyOption, [:]),
            (BookSource(bookSourceName: "Config header", bookSourceUrl: origin,
                        customConfig: #"{"headers":{"CONTENT-TYPE":"\#(form)"}}"#), bodyOption, [:]),
            (BookSource(bookSourceName: "Login header", bookSourceUrl: origin), bodyOption,
             ["source.loginHeader": #"{"Content-Type":"\#(form)"}"#]),
            (BookSource(bookSourceName: "Directive override", bookSourceUrl: origin,
                        header: #"{"Content-Type":"application/json"}"#),
             #",{"headers":{"content-type":"\#(form)"},"body":{"a":"1&2","b":"2"}}"#, [:]),
            (BookSource(bookSourceName: "Configured body", bookSourceUrl: origin,
                        header: #"{"content-type":"\#(form)"}"#,
                        customConfig: #"{"body":{"a":"1&2","b":"2"}}"#), "", [:])
        ]
        for (source, suffix, values) in fixtures {
            SourceTransportURLProtocol.registry.configure([origin: .http(200, [:], "accepted")])
            let request = SourceRequestBuilder().buildPageRequest(source: source, urlText: origin + suffix,
                                                                  persistentValues: values)
            _ = try await load(request).get()
            let sent = try XCTUnwrap(SourceTransportURLProtocol.registry.requests.first)
            XCTAssertEqual(sent.httpMethod, "POST")
            XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), form)
            XCTAssertEqual(try readBody(sent), Data("a=1%262&b=2".utf8))
            XCTAssertEqual(request.headers.keys.filter { $0.lowercased() == "content-type" }.count, 1)
        }
    }

    func testStringBodyRetainsItsExistingEncodingAndContentType() async throws {
        for text in ["a=1%262&b=2", #"{"q":"a&b"}"#] {
            let options = String(decoding: try JSONSerialization.data(withJSONObject: ["body": text]), as: UTF8.self)
            let source = BookSource(bookSourceName: "String fixture", bookSourceUrl: origin,
                                    customConfig: options)
            let requests = [
                SourceRequestBuilder().buildPageRequest(source: source, urlText: origin),
                SourceRequestBuilder().buildPageRequest(source: source, urlText: origin + "," + options)
            ]
            for request in requests {
                SourceTransportURLProtocol.registry.configure([origin: .http(200, [:], "accepted")])
                _ = try await load(request).get()
                let sent = try XCTUnwrap(SourceTransportURLProtocol.registry.requests.first)
                XCTAssertEqual(try readBody(sent), Data(text.utf8))
                XCTAssertNil(request.headers.first { $0.key.lowercased() == "content-type" })
            }
        }
    }

    func testDirectiveJSONHeaderOverridesSourceFormForConfiguredObjectBody() async throws {
        let source = BookSource(bookSourceName: "JSON override fixture", bookSourceUrl: origin,
                                header: #"{"Content-Type":"application/x-www-form-urlencoded"}"#,
                                customConfig: #"{"body":{"a":"1&2","page":2}}"#)
        let request = SourceRequestBuilder().buildPageRequest(source: source,
            urlText: origin + #"@Header:{"content-type":"application/json; charset=UTF-8"}"#)
        SourceTransportURLProtocol.registry.configure([origin: .http(200, [:], "accepted")])
        _ = try await load(request).get()
        let sent = try XCTUnwrap(SourceTransportURLProtocol.registry.requests.first)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=UTF-8")
        XCTAssertEqual(try readBody(sent), Data(#"{"a":"1&2","page":2}"#.utf8))
        XCTAssertEqual(request.headers.keys.filter { $0.lowercased() == "content-type" }.count, 1)
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

    func testAnonymousRequestDiscardsExplicitAndSessionCredentials() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SourceTransportURLProtocol.self]
        configuration.httpShouldSetCookies = true
        configuration.httpAdditionalHeaders = ["Authorization": "Bearer session-fixture", "Cookie": "session=fixture",
                                               "X-Session-Token": "fixture"]
        let url = try XCTUnwrap(URL(string: origin))
        let stored = try XCTUnwrap(HTTPCookie(properties: [.name: "automatic", .value: "fixture",
                                                          .domain: "source.fixture.invalid", .path: "/"]))
        configuration.httpCookieStorage?.setCookie(stored)
        await cookieStore.storeSetCookieHeaders(["Set-Cookie": "login=fixture; Path=/"], for: url)
        SourceTransportURLProtocol.registry.configure([origin: .http(200, [:], "library")])
        var headers = credentials
        headers["Cookie2"] = "legacy=fixture"
        headers["Proxy-Authorization"] = "Basic fixture"
        let response = try await loadAnonymous(origin, headers: headers, configuration: configuration).get()
        XCTAssertEqual(response.body, "library")
        let request = try XCTUnwrap(SourceTransportURLProtocol.registry.requests.first)
        for field in ["Cookie", "Cookie2", "Authorization", "Proxy-Authorization", "X-Session-Token"] {
            XCTAssertNil(request.value(forHTTPHeaderField: field), "Anonymous request inherited \(field)")
        }
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/html")
        let retained = await cookieStore.cookieHeader(for: url)
        XCTAssertEqual(retained, "login=fixture")
    }

    func testAnonymousRedirectsNeitherSendNorReplaceLoginCookies() async throws {
        for target in ["https://source.fixture.invalid/library.js", "https://cdn.fixture.invalid/library.js"] {
            let originURL = try XCTUnwrap(URL(string: origin))
            let targetURL = try XCTUnwrap(URL(string: target))
            await cookieStore.clearAllCookies()
            await cookieStore.storeSetCookieHeaders(["Set-Cookie": "login=origin; Path=/"], for: originURL)
            if targetURL.host != originURL.host {
                await cookieStore.storeSetCookieHeaders(["Set-Cookie": "login=destination; Path=/"], for: targetURL)
            }
            let originCookie = await cookieStore.cookieHeader(for: originURL)
            let targetCookie = await cookieStore.cookieHeader(for: targetURL)
            for redirect in [SourceTransportReply.http(302, ["Location": target, "Set-Cookie": "login=redirect; Path=/"], ""),
                             .http(200, ["Set-Cookie": "login=redirect; Path=/"], "<meta http-equiv='refresh' content='0;url=\(target)'>")] {
                SourceTransportURLProtocol.registry.configure([
                    origin: redirect, target: .http(200, ["Set-Cookie": "login=script; Path=/"], "library")
                ])
                _ = try await loadAnonymous(origin, headers: credentials).get()
                let requests = SourceTransportURLProtocol.registry.requests
                XCTAssertEqual(requests.count, 2)
                for request in requests {
                    XCTAssertFalse(request.httpShouldHandleCookies)
                    XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
                    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                }
                let retainedOrigin = await cookieStore.cookieHeader(for: originURL)
                let retainedTarget = await cookieStore.cookieHeader(for: targetURL)
                XCTAssertEqual(retainedOrigin, originCookie)
                XCTAssertEqual(retainedTarget, targetCookie)
            }
        }
    }

    func testAnonymousResponseDoesNotPopulateSessionCookieStorage() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SourceTransportURLProtocol.self]
        configuration.httpShouldSetCookies = true
        let url = try XCTUnwrap(URL(string: origin))
        let cookieStorage = try XCTUnwrap(configuration.httpCookieStorage)
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = URLSessionSourceNetworkClient(session: session, cookieStore: cookieStore)
        SourceTransportURLProtocol.registry.configure([origin: .http(200, ["Set-Cookie": "library=fixture; Path=/"], "library")])
        _ = try await client.load(SourceRequest(url: url, method: .get, headers: [:], body: nil,
                                               expectedCharset: nil, timeout: 2, usesCookies: false)).get()
        XCTAssertTrue((cookieStorage.cookies(for: url) ?? []).isEmpty)
        XCTAssertTrue(session.configuration.httpShouldSetCookies)
        XCTAssertTrue(session.configuration.httpCookieStorage === cookieStorage)
        let stored = await cookieStore.cookies(for: url)
        XCTAssertTrue(stored.isEmpty)
    }

    func testAnonymousRequestRejectsEmbeddedURLCredentials() async {
        let result = await loadAnonymous("https://account:fixture@source.fixture.invalid/library.js")
        guard case .failure = result else { return XCTFail("Anonymous request accepted embedded URL credentials") }
        XCTAssertTrue(SourceTransportURLProtocol.registry.requests.isEmpty)
    }

    func testAnonymousCooldownResponseDoesNotRetryOrClearLogin() async throws {
        let url = try XCTUnwrap(URL(string: origin))
        await cookieStore.storeSetCookieHeaders(["Set-Cookie": "login=fixture; Path=/"], for: url)
        let body = "<script>alert('搜索间隔: 30 秒');history.go(-1)</script>"
        SourceTransportURLProtocol.registry.configure([origin: .http(200, [:], body)])
        let response = try await loadAnonymous(origin).get()
        XCTAssertEqual(response.body, body)
        XCTAssertEqual(SourceTransportURLProtocol.registry.requests.count, 1)
        let retained = await cookieStore.cookieHeader(for: url)
        XCTAssertEqual(retained, "login=fixture")
    }

    func testOrdinaryRequestStillSendsAndUpdatesLoginCookiesByDefault() async throws {
        let url = try XCTUnwrap(URL(string: origin))
        await cookieStore.storeSetCookieHeaders(["Set-Cookie": "login=before; Path=/"], for: url)
        SourceTransportURLProtocol.registry.configure([origin: .http(200, ["Set-Cookie": "login=after; Path=/"], "chapter")])
        _ = try await load(origin).get()
        let request = try XCTUnwrap(SourceTransportURLProtocol.registry.requests.first)
        XCTAssertTrue(request.httpShouldHandleCookies)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "login=before")
        let stored = await cookieStore.cookieHeader(for: url)
        XCTAssertEqual(stored, "login=after")
    }

    private func readBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { return body }
            body.append(contentsOf: buffer.prefix(count))
        }
    }

    private func loadAnonymous(_ address: String, headers: [String: String] = [:],
                               configuration: URLSessionConfiguration? = nil) async -> Result<SourceResponse, SourceEngineError> {
        let isolatedConfiguration = configuration ?? URLSessionConfiguration.ephemeral
        isolatedConfiguration.protocolClasses = [SourceTransportURLProtocol.self]
        let session = URLSession(configuration: isolatedConfiguration)
        defer { session.invalidateAndCancel() }
        let client = URLSessionSourceNetworkClient(session: session, cookieStore: cookieStore)
        return await client.load(SourceRequest(url: URL(string: address)!, method: .get, headers: headers,
                                               body: nil, expectedCharset: nil, timeout: 2, usesCookies: false))
    }

    private func load(_ address: String, method: SourceHTTPMethod = .get,
                      headers: [String: String] = [:], body: Data? = nil) async -> Result<SourceResponse, SourceEngineError> {
        await load(SourceRequest(url: URL(string: address)!, method: method, headers: headers,
                                 body: body, expectedCharset: nil, timeout: 2))
    }

    private func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SourceTransportURLProtocol.self]
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = URLSessionSourceNetworkClient(session: session, cookieStore: cookieStore)
        return await client.load(request)
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
