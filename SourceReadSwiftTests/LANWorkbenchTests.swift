import XCTest
@testable import SourceReadSwift

final class LANWorkbenchTests: XCTestCase {
    private func request(token: String? = nil, method: String = "GET", origin: String? = nil,
                         host: String = "192.168.1.3:8080", extra: [String: String] = [:]) -> LightweightHTTPRequest {
        var headers = extra
        headers["host"] = host
        if let token { headers["x-sourceread-token"] = token }
        if let origin { headers["origin"] = origin }
        return LightweightHTTPRequest(method: method, target: "/api/status", path: "/api/status", headers: headers, body: Data())
    }

    func testCapabilityRequiresHeaderAndExpiresOnRenewAndStop() {
        let access = LANWorkbenchAccess()
        XCTAssertFalse(access.permits(request(token: "")))
        let first = access.renew()
        XCTAssertEqual(first.count, 32)
        XCTAssertTrue(first.allSatisfy { $0.isHexDigit })
        XCTAssertFalse(access.permits(request()))
        XCTAssertFalse(access.permits(request(token: first + "a")))
        XCTAssertTrue(access.permits(request(token: first)))
        XCTAssertFalse(access.permits(request(extra: ["cookie": "token=" + first])))
        let second = access.renew()
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(access.permits(request(token: first)))
        XCTAssertTrue(access.permits(request(token: second)))
        access.revoke()
        XCTAssertFalse(access.permits(request(token: second)))
    }

    func testBrowserOriginMustMatchAuthorityAndPreflightIsNotAuthenticated() {
        let access = LANWorkbenchAccess(); let token = access.renew()
        XCTAssertTrue(access.permits(request(token: token, origin: "http://192.168.1.3:8080")))
        XCTAssertTrue(access.permits(request(token: token, origin: "http://localhost", host: "localhost:80")))
        for origin in ["null", "https://192.168.1.3:8080", "http://192.168.1.3:8081", "http://evil.test",
                       "http://user@192.168.1.3:8080", "http://192.168.1.3:8080/path"] {
            XCTAssertFalse(access.permits(request(token: token, origin: origin)), origin)
        }
        XCTAssertFalse(access.permits(request(token: token, method: "OPTIONS")))
        XCTAssertFalse(access.permits(request(token: token, extra: ["sec-fetch-site": "cross-site"])))
    }

    func testOfflineDocumentNeverEmbedsCapabilityOrThirdPartyResources() {
        let html = LANWorkbenchDocument.html
        XCTAssertTrue(html.contains("仅保留于当前页面"))
        XCTAssertTrue(html.contains("X-SourceRead-Token"))
        XCTAssertTrue(html.contains("每页 20 条"))
        XCTAssertFalse(html.contains("localStorage"))
        XCTAssertFalse(html.contains("sessionStorage"))
        XCTAssertFalse(html.contains("<script src="))
        XCTAssertFalse(html.contains("onclick=\"quickDebugSource"))
        XCTAssertTrue(html.contains("手机端任务可能仍在完成"))
    }

    @MainActor func testActualServerPairingImportLibraryEditToggleExportDeleteAndRevocation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SourceStore(persistence: SourcePersistence(rootURL: root))
        let server = LightweightHTTPServer(sourceStore: store)
        server.onJSONReceived = { text in
            do { return .success(try store.importJSON(text).userMessage) }
            catch { return .failure(error) }
        }
        server.start(); defer { server.stop() }
        for _ in 0..<150 {
            if server.isRunning { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(server.isRunning, server.lastError ?? "server not ready")
        guard server.isRunning else { return }
        let token = server.pairingToken
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 8
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        func send(_ path: String, method: String = "GET", authorized: Bool = true,
                  body: Data? = nil, origin: String? = nil) async throws -> (Data, HTTPURLResponse) {
            var req = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)" + path)!)
            req.httpMethod = method; req.httpBody = body
            if authorized { req.setValue(token, forHTTPHeaderField: "X-SourceRead-Token") }
            if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            if let origin { req.setValue(origin, forHTTPHeaderField: "Origin") }
            let (data, response) = try await session.data(for: req)
            return (data, try XCTUnwrap(response as? HTTPURLResponse))
        }
        let (page, pageResponse) = try await send("/", authorized: false)
        XCTAssertEqual(pageResponse.statusCode, 200)
        XCTAssertFalse(String(decoding: page, as: UTF8.self).contains(token))
        XCTAssertNil(pageResponse.value(forHTTPHeaderField: "Access-Control-Allow-Origin"))
        XCTAssertEqual(pageResponse.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(pageResponse.value(forHTTPHeaderField: "Connection"), "close")
        XCTAssertTrue(pageResponse.value(forHTTPHeaderField: "Content-Security-Policy")?.contains("frame-ancestors 'none'") == true)
        let (_, health) = try await send("/health", authorized: false)
        XCTAssertEqual(health.statusCode, 200)
        let (_, unauthorized) = try await send("/api/sources/export", authorized: false)
        XCTAssertEqual(unauthorized.statusCode, 401)
        let (_, queryToken) = try await send("/api/status?token=" + token, authorized: false)
        XCTAssertEqual(queryToken.statusCode, 401)
        let (_, crossSite) = try await send("/api/status", origin: "http://untrusted.invalid")
        XCTAssertEqual(crossSite.statusCode, 401)
        let source = BookSource(bookSourceName: "测试 ' <书源>", bookSourceUrl: "https://novel.example/path?a=1&b=2")
        let encoded = try JSONEncoder().encode(source)
        let (_, blockedImport) = try await send("/import", method: "POST", authorized: false, body: encoded)
        XCTAssertEqual(blockedImport.statusCode, 401)
        XCTAssertTrue(store.sources.isEmpty)
        let (_, imported) = try await send("/api/sources/import", method: "POST", body: encoded)
        XCTAssertEqual(imported.statusCode, 200)
        XCTAssertEqual(store.sources.count, 1)
        let (library, libraryResponse) = try await send("/api/sources/health")
        XCTAssertEqual(libraryResponse.statusCode, 200)
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: library) as? [String: Any])
        XCTAssertEqual((rows["items"] as? [[String: Any]])?.count, 1)
        var query = URLComponents(); query.queryItems = [URLQueryItem(name: "url", value: source.bookSourceUrl)]
        let (single, singleResponse) = try await send("/api/source?" + (query.percentEncodedQuery ?? ""))
        XCTAssertEqual(singleResponse.statusCode, 200)
        let singleObject = try XCTUnwrap(JSONSerialization.jsonObject(with: single) as? [String: Any])
        XCTAssertEqual((singleObject["data"] as? [String: Any])?["bookSourceName"] as? String, source.bookSourceName)
        let (_, missing) = try await send("/api/source?url=https%3A%2F%2Fmissing.invalid")
        XCTAssertEqual(missing.statusCode, 404)
        let toggle = try JSONSerialization.data(withJSONObject: ["url": source.bookSourceUrl, "enabled": false])
        let (_, toggled) = try await send("/api/sources/toggle", method: "POST", body: toggle)
        XCTAssertEqual(toggled.statusCode, 200)
        XCTAssertFalse(store.sources[0].enabled)
        let (exported, exportedResponse) = try await send("/api/sources/export")
        XCTAssertEqual(exportedResponse.statusCode, 200)
        let backup = try JSONDecoder().decode(SourceLibrarySnapshot.self, from: exported)
        XCTAssertEqual(backup.sources.count, 1)
        let deleted = try JSONSerialization.data(withJSONObject: ["url": source.bookSourceUrl])
        let (_, deleteResponse) = try await send("/api/sources/delete", method: "POST", body: deleted)
        XCTAssertEqual(deleteResponse.statusCode, 200)
        XCTAssertTrue(store.sources.isEmpty)
        XCTAssertFalse(server.logMessages.contains { $0.contains(token) })
        server.stop()
        XCTAssertTrue(server.pairingToken.isEmpty)
    }
}
