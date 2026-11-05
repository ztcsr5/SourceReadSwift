import XCTest
import UIKit
@testable import SourceReadSwift

final class RemoteComicImageTests: XCTestCase {
    func testComicFailureStatusAndAuthenticatedCacheContextStaySeparate() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ComicImageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let loader = RemoteImageLoader(session: session)
        let url = try XCTUnwrap(URL(string: "https://comic-image-fixture.invalid/page.png"))
        ComicImageURLProtocol.setSuccess(true)
        let validHeaders = ["Referer": "https://comic.example/chapter/1"]
        let loaded = await loader.comicPage(for: url, headers: validHeaders, maxPixelSize: 4096)
        XCTAssertNotNil(try loaded.get())
        XCTAssertNotNil(loader.cachedComicPage(for: url, headers: validHeaders, maxPixelSize: 4096))
        XCTAssertNil(loader.cachedComicPage(for: url, headers: [:], maxPixelSize: 4096))
        let rejected = await loader.comicPage(for: url, headers: [:], maxPixelSize: 4096)
        guard case .failure(let reason) = rejected else { return XCTFail("A different context must not reuse the authenticated bitmap") }
        XCTAssertEqual(reason, .http(403))
    }

    func testHTTPFailureEndsAndFollowingRetryCanDecodeImage() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ComicImageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let loader = RemoteImageLoader(session: session)
        let url = URL(string: "https://comic-image-fixture.invalid/page.png")!
        ComicImageURLProtocol.setSuccess(false)
        let failed = await loader.image(for: url, headers: ["Referer": "https://comic.example/chapter/1"])
        XCTAssertNil(failed)
        XCTAssertNil(loader.cachedImage(for: url))
        ComicImageURLProtocol.setSuccess(true)
        let loaded = await loader.image(for: url, headers: ["Referer": "https://comic.example/chapter/1"])
        XCTAssertNotNil(loaded)
        XCTAssertNotNil(loader.cachedImage(for: url))
    }

    func testComicDistinguishesEmptyCorruptAndRejectedPages() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ComicImageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let loader = RemoteImageLoader(session: session)
        let headers = ["Referer": "https://comic.example/chapter/1"]
        let failures: [(String, ComicImageFailure)] = [
            ("/empty", .emptyResponse), ("/invalid", .invalidImage), ("/unaccepted", .http(422))
        ]
        for (path, expected) in failures {
            let url = try XCTUnwrap(URL(string: "https://comic-image-fixture.invalid" + path))
            let result = await loader.comicPage(for: url, headers: headers, maxPixelSize: 4096)
            guard case .failure(let actual) = result else { return XCTFail("Expected a failed page for \(path)") }
            XCTAssertEqual(actual, expected)
            XCTAssertNil(loader.cachedComicPage(for: url, headers: headers, maxPixelSize: 4096))
        }
        XCTAssertTrue(ComicImageFailure.http(422).canRefreshAddress)
        XCTAssertFalse(ComicImageFailure.timedOut.canRefreshAddress)
        let good = try XCTUnwrap(URL(string: "https://comic-image-fixture.invalid/good"))
        let result = await loader.comicPage(for: good, headers: headers, maxPixelSize: 4096)
        XCTAssertNotNil(try result.get(), "A failed page must not prevent another page from decoding")
    }

    func testOfflinePageDecodesFromDiskWithoutAnHTTPTransport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let address = folder.appendingPathComponent("offline.img")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAIAAAASFvFNAAAAGklEQVR42mNgYGhg0ADiACBmCACygTggoAEAMGgE4bJ9Q/wAAAAASUVORK5CYII=")!
        try png.write(to: address)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ComicImageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let loader = RemoteImageLoader(session: session)
        let result = await loader.comicPage(for: address, headers: [:], maxPixelSize: 4096)
        XCTAssertNotNil(try result.get())
        let export = await loader.comicBytesForArchive(ComicImageRequest(url: address.absoluteString, headers: [:]))
        guard case .failure(.invalidResponse) = export else {
            return XCTFail("Source requests cannot treat arbitrary files as download inputs")
        }
    }

    func testCancellingOneReaderKeepsTheSharedPageButLastReaderCancelsTheNetwork() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeldComicImageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let loader = RemoteImageLoader(session: session)
        let url = try XCTUnwrap(URL(string: "https://held-comic.invalid/\(UUID().uuidString)"))
        let first = Task { await loader.comicPage(for: url, headers: [:], maxPixelSize: 4096) }
        let second = Task { await loader.comicPage(for: url, headers: [:], maxPixelSize: 4096) }
        for _ in 0..<200 {
            if loader.comicSubscriberCount(for: url, headers: [:], maxPixelSize: 4096) == 2,
               HeldComicImageURLProtocol.counts(url).started == 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(loader.comicSubscriberCount(for: url, headers: [:], maxPixelSize: 4096), 2)
        first.cancel()
        for _ in 0..<200 {
            if loader.comicSubscriberCount(for: url, headers: [:], maxPixelSize: 4096) == 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(loader.comicSubscriberCount(for: url, headers: [:], maxPixelSize: 4096), 1)
        XCTAssertEqual(HeldComicImageURLProtocol.counts(url).stopped, 0)
        second.cancel()
        for _ in 0..<200 {
            if HeldComicImageURLProtocol.counts(url).stopped == 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(HeldComicImageURLProtocol.counts(url).started, 1)
        XCTAssertEqual(HeldComicImageURLProtocol.counts(url).stopped, 1)
        XCTAssertEqual(loader.comicSubscriberCount(for: url, headers: [:], maxPixelSize: 4096), 0)
        let firstResult = await first.value
        let secondResult = await second.value
        guard case .failure(.cancelled) = firstResult, case .failure(.cancelled) = secondResult else {
            return XCTFail("Both cancelled subscribers must finish without caching a bitmap")
        }
        XCTAssertNil(loader.cachedComicPage(for: url, headers: [:], maxPixelSize: 4096))
    }

    func testComicTransfersStayBoundedAndCancelledWaitersDoNotStart() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeldComicImageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let loader = RemoteImageLoader(session: session)
        let urls = try (0..<7).map { index in
            try XCTUnwrap(URL(string: "https://held-comic.invalid/\(UUID().uuidString)-\(index)"))
        }
        let readers = urls.map { url in Task { await loader.comicPage(for: url, headers: [:], maxPixelSize: 4096) } }
        for _ in 0..<200 {
            if urls.reduce(0, { $0 + HeldComicImageURLProtocol.counts($1).started }) == 4 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(urls.reduce(0) { $0 + HeldComicImageURLProtocol.counts($1).started }, 4)
        let queued = urls.indices.filter { HeldComicImageURLProtocol.counts(urls[$0]).started == 0 }
        for index in queued { readers[index].cancel() }
        for index in queued { _ = await readers[index].value }
        readers.forEach { $0.cancel() }
        for reader in readers { _ = await reader.value }
        XCTAssertEqual(urls.reduce(0) { $0 + HeldComicImageURLProtocol.counts($1).started }, 4,
                       "Cancelled queued pages must not begin their transfers")
    }
}

private final class HeldComicImageURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var started: [URL: Int] = [:]
    private static var stopped: [URL: Int] = [:]
    static func counts(_ url: URL) -> (started: Int, stopped: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (started[url, default: 0], stopped[url, default: 0])
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "held-comic.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock()
        Self.started[url, default: 0] += 1
        Self.lock.unlock()
    }
    override func stopLoading() {
        guard let url = request.url else { return }
        Self.lock.lock()
        Self.stopped[url, default: 0] += 1
        Self.lock.unlock()
    }
}

private final class ComicImageURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var success = false
    static func setSuccess(_ value: Bool) { lock.lock(); success = value; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "comic-image-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let ok = Self.success; Self.lock.unlock()
        let authorized = request.value(forHTTPHeaderField: "Referer") == "https://comic.example/chapter/1"
        let path = request.url?.path ?? ""
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAIAAAASFvFNAAAAGklEQVR42mNgYGhg0ADiACBmCACygTggoAEAMGgE4bJ9Q/wAAAAASUVORK5CYII=")!
        let (code, body): (Int, Data)
        switch path {
        case "/empty": (code, body) = (200, Data())
        case "/invalid": (code, body) = (200, Data("<html>not an image</html>".utf8))
        case "/unaccepted": (code, body) = (422, Data("unprocessable".utf8))
        case "/good": (code, body) = (200, data)
        default: (code, body) = ok && authorized ? (200, data) : (403, Data("forbidden".utf8))
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
