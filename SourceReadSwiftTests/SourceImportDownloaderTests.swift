import XCTest
@testable import SourceReadSwift

@MainActor
final class SourceImportDownloaderTests: XCTestCase {
    // MARK: - HTTP status, size and payload shape

    func testDownloadReturnsPayloadForSuccessfulResponse() async {
        let body = #"[{"bookSourceName":"A","bookSourceUrl":"https://a.example"}]"#
        let network = StubImportNetwork(.success(makeResponse(body: body)))
        let downloader = SourceImportDownloader(client: network)

        let result = await downloader.download(from: "https://example.com/sources.json")

        guard case .success(let payload) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(payload.statusCode, 200)
        XCTAssertEqual(payload.text, body)
        XCTAssertEqual(payload.data, Data(body.utf8))
        XCTAssertEqual(payload.url.absoluteString, "https://example.com/sources.json")
    }

    func testDownloadRejectsHTTPErrorStatus() async {
        let network = StubImportNetwork(.success(makeResponse(statusCode: 404, body: "not found")))
        let downloader = SourceImportDownloader(client: network)

        let result = await downloader.download(from: "https://example.com/sources.json")

        XCTAssertEqual(failure(from: result), .httpStatus(404))
    }

    func testDownloadRejectsOversizedDeclaredContentLength() async {
        let network = StubImportNetwork(.success(makeResponse(
            headers: ["Content-Type": "application/json", "Content-Length": "104857600"],
            body: "{}"
        )))
        let downloader = SourceImportDownloader(client: network, maximumBytes: 1024)

        let result = await downloader.download(from: "https://example.com/sources.json")

        XCTAssertEqual(failure(from: result), .responseTooLarge(104857600))
    }

    func testDownloadRejectsOversizedBody() async {
        let body = String(repeating: "a", count: 64)
        let network = StubImportNetwork(.success(makeResponse(body: body)))
        let downloader = SourceImportDownloader(client: network, maximumBytes: 16)

        let result = await downloader.download(from: "https://example.com/sources.json")

        XCTAssertEqual(failure(from: result), .responseTooLarge(64))
    }

    func testDownloadRejectsEmptyResponse() async {
        let network = StubImportNetwork(.success(makeResponse(body: "")))
        let downloader = SourceImportDownloader(client: network)

        let result = await downloader.download(from: "https://example.com/sources.json")

        XCTAssertEqual(failure(from: result), .emptyResponse)
    }

    // MARK: - Challenge / HTML detection

    func testDownloadDetectsCloudflareChallenge() async {
        let body = """
        <!DOCTYPE html><html><head><title>Just a moment...</title></head>
        <body>Checking your browser before accessing example.com.</body></html>
        """
        let network = StubImportNetwork(.success(makeResponse(
            headers: ["Content-Type": "text/html", "Server": "cloudflare"],
            body: body
        )))
        let downloader = SourceImportDownloader(client: network)

        let result = await downloader.download(from: "https://example.com/sources.json")

        XCTAssertEqual(failure(from: result), .challengePage)
    }

    func testDownloadDetectsChallengeFromSingleMarkerPlusCloudflareServer() async {
        let body = #"<html><body><script src="/cdn-cgi/challenge-platform/x.js"></script></body></html>"#
        let network = StubImportNetwork(.success(makeResponse(
            headers: ["Content-Type": "text/html", "Server": "cloudflare"],
            body: body
        )))
        let downloader = SourceImportDownloader(client: network)

        let result = await downloader.download(from: "https://example.com/sources.json")

        XCTAssertEqual(failure(from: result), .challengePage)
    }

    func testDownloadKeepsJSONThatMentionsChallengeWords() async {
        let body = #"[{"bookSourceName":"checking your browser","bookSourceUrl":"https://example.com"}]"#
        let network = StubImportNetwork(.success(makeResponse(body: body)))
        let downloader = SourceImportDownloader(client: network)

        let result = await downloader.download(from: "https://example.com/sources.json")

        guard case .success = result else {
            return XCTFail("valid JSON must win over challenge markers: \(result)")
        }
    }

    func testDownloadRejectsHTMLPageThatIsNotJSON() async {
        let body = "<!DOCTYPE html><html><body>404 Not Found</body></html>"
        let network = StubImportNetwork(.success(makeResponse(
            headers: ["Content-Type": "text/html"],
            body: body
        )))
        let downloader = SourceImportDownloader(client: network)

        let result = await downloader.download(from: "https://example.com/sources.json")

        XCTAssertEqual(failure(from: result), .notSourceJSON)
    }

    // MARK: - URL normalization

    func testNormalizesGitHubBlobURLToRaw() {
        let normalized = SourceImportURLNormalizer.normalizedString(
            "https://github.com/ztcsr5/SourceReadSwift/blob/main/sources.json"
        )

        XCTAssertEqual(
            normalized,
            "https://raw.githubusercontent.com/ztcsr5/SourceReadSwift/main/sources.json"
        )
    }

    func testNormalizesGiteeGitLabAndBitbucketBlobURLs() {
        XCTAssertEqual(
            SourceImportURLNormalizer.normalizedString("https://gitee.com/user/repo/blob/master/a.json"),
            "https://gitee.com/user/repo/raw/master/a.json"
        )
        XCTAssertEqual(
            SourceImportURLNormalizer.normalizedString("https://gitlab.com/user/repo/-/blob/main/a.json"),
            "https://gitlab.com/user/repo/-/raw/main/a.json"
        )
        XCTAssertEqual(
            SourceImportURLNormalizer.normalizedString("https://bitbucket.org/user/repo/src/main/a.json"),
            "https://bitbucket.org/user/repo/raw/main/a.json"
        )
    }

    func testNormalizerAddsSchemeForBareKnownHosts() {
        XCTAssertEqual(
            SourceImportURLNormalizer.normalizedString("github.com/user/repo/blob/main/a.json"),
            "https://raw.githubusercontent.com/user/repo/main/a.json"
        )
    }

    func testNormalizerTrimsPastedPunctuationAndRejectsNonHTTP() {
        XCTAssertEqual(
            SourceImportURLNormalizer.normalizedString("  https://example.com/a.json。  "),
            "https://example.com/a.json"
        )
        XCTAssertNil(SourceImportURLNormalizer.url(from: "ftp://example.com/a.json"))
        XCTAssertNil(SourceImportURLNormalizer.url(from: "not a url"))
    }

    // MARK: - Store integration

    func testStoreImportsDownloadedJSON() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = #"[{"bookSourceName":"下载源","bookSourceUrl":"https://download.example","searchUrl":"https://download.example/s?q={{keyword}}"}]"#
        let network = StubImportNetwork(.success(makeResponse(body: json)))
        let downloader = SourceImportDownloader(client: network)

        let result = try await store.importSmartInputAsync(
            "https://example.com/sources.json",
            downloader: downloader
        )

        XCTAssertEqual(result.input.kind, .url)
        XCTAssertEqual(result.report.addedBookSources, 1)
        XCTAssertEqual(store.sources.map(\.bookSourceName), ["下载源"])
        XCTAssertEqual(result.downloadedFrom?.absoluteString, "https://example.com/sources.json")
        try? FileManager.default.removeItem(at: root)
    }

    func testStorePropagatesDownloadFailure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let network = StubImportNetwork(.success(makeResponse(statusCode: 404, body: "not found")))
        let downloader = SourceImportDownloader(client: network)

        do {
            _ = try await store.importSmartInputAsync(
                "https://example.com/sources.json",
                downloader: downloader
            )
            XCTFail("expected HTTP 404 to throw")
        } catch let error as SourceImportError {
            XCTAssertEqual(error, .httpStatus(404))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertTrue(store.sources.isEmpty)
        try? FileManager.default.removeItem(at: root)
    }

    func testStoreImportsGBKEncodedJSONAfterUTF8DecodeFails() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = #"[{"bookSourceName":"中文书源","bookSourceUrl":"https://gbk.example","searchUrl":"https://gbk.example/s?q={{keyword}}"}]"#
        let gbkData = LegadoCharset.encode(json, charset: "gbk")!
        StubURLProtocol.registry.set { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json; charset=gbk"]
            )!
            return (response, gbkData)
        }
        defer { StubURLProtocol.registry.reset() }

        let result = try await store.importSmartInputAsync(
            "https://gbk.example.com/sources.json",
            downloader: makeRealClientDownloader()
        )

        XCTAssertEqual(result.report.addedBookSources, 1)
        XCTAssertEqual(store.sources.map(\.bookSourceName), ["中文书源"])
        try? FileManager.default.removeItem(at: root)
    }
    // MARK: - Real URLSession client

    func testURLSessionClientDecodesGBKResponseBeforeImport() async {
        let gbkData = LegadoCharset.encode("中文书源", charset: "gbk")!
        StubURLProtocol.registry.set { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json; charset=gbk"]
            )!
            return (response, gbkData)
        }
        defer { StubURLProtocol.registry.reset() }

        let result = await makeRealClientDownloader().download(from: "https://gbk.example.com/sources.json")

        guard case .success(let payload) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(payload.text, "中文书源")
        XCTAssertEqual(payload.data, gbkData)
    }

    func testURLSessionClientSurfaces404ToDownloader() async {
        StubURLProtocol.registry.set { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/plain"]
            )!
            return (response, Data("not found".utf8))
        }
        defer { StubURLProtocol.registry.reset() }

        let result = await makeRealClientDownloader().download(from: "https://example.com/sources.json")

        XCTAssertEqual(failure(from: result), .httpStatus(404))
    }

    // MARK: - Helpers

    private func makeRealClientDownloader() -> SourceImportDownloader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = URLSessionSourceNetworkClient(
            session: session,
            cookieStore: SourceCookieStore(storageURL: nil)
        )
        return SourceImportDownloader(client: client)
    }

    private func makeResponse(
        url: String = "https://example.com/sources.json",
        statusCode: Int = 200,
        headers: [String: String] = ["Content-Type": "application/json; charset=utf-8"],
        body: String,
        data: Data? = nil
    ) -> SourceResponse {
        SourceResponse(
            url: URL(string: url)!,
            statusCode: statusCode,
            headers: headers,
            body: body,
            data: data ?? Data(body.utf8)
        )
    }

    private func failure(from result: Result<SourceImportPayload, SourceImportError>) -> SourceImportError? {
        guard case .failure(let error) = result else {
            XCTFail("expected failure, got \(result)")
            return nil
        }
        return error
    }
}

private final class StubImportNetwork: SourceNetworkClient, @unchecked Sendable {
    private let result: Result<SourceResponse, SourceEngineError>
    private let lock = NSLock()
    private var urls: [String] = []

    init(_ result: Result<SourceResponse, SourceEngineError>) {
        self.result = result
    }

    var requestedURLs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        lock.lock()
        urls.append(request.url.absoluteString)
        lock.unlock()
        return result
    }
}