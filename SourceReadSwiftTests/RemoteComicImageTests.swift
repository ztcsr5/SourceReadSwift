import XCTest
import UIKit
@testable import SourceReadSwift

final class RemoteComicImageTests: XCTestCase {
    func testResponsePolicyRejectsOversizedAndMalformedDeclaredLengthsBeforeBody() throws {
        let url = URL(string: "https://comic.fixture.invalid/page")!
        for (header, expected) in [("1025", ComicImageFailure.tooLarge),
                                    ("999999999999999999999999", .tooLarge),
                                    ("-1", .invalidResponse), ("not-a-number", .invalidResponse)] {
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                       headerFields: ["content-length": header]))
            XCTAssertEqual(ComicImageResponsePolicy.failure(for: response, limit: 1024), expected)
        }
        for headers in [[String: String](), ["Content-Length": "1024"]] {
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers))
            XCTAssertNil(ComicImageResponsePolicy.failure(for: response, limit: 1024))
        }
    }

    func testOversizedComicResponsesStopBeforeTheServerFinishes() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OversizedComicImageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let loader = RemoteImageLoader(session: session)

        for mode in ["declared", "chunked"] {
            let url = try XCTUnwrap(URL(string: "https://oversized-comic.invalid/\(mode)/\(UUID().uuidString)"))
            let finished = expectation(description: "\(mode) response must return without receiving EOF")
            let load = Task {
                let result = await loader.comicBytesForArchive(ComicImageRequest(url: url.absoluteString, headers: [:]))
                finished.fulfill()
                return result
            }
            let wait = await XCTWaiter.fulfillment(of: [finished], timeout: 4)
            if wait != .completed { load.cancel() }
            let result = await load.value
            XCTAssertEqual(wait, .completed)
            guard case .failure(.tooLarge) = result else {
                XCTFail("Expected the \(mode) body to fail at the application byte limit")
                continue
            }
            for _ in 0..<100 {
                if OversizedComicImageURLProtocol.hasStopped(url) { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertTrue(OversizedComicImageURLProtocol.hasStopped(url), "Rejecting an image must stop the actual transfer")
        }
    }

    func testLongComicStripRetainsReadableWidthWithinTheDecodedPixelBudget() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 6000), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 6000))
        }
        let address = folder.appendingPathComponent("long-strip.png")
        try XCTUnwrap(image.pngData()).write(to: address)
        let result = await RemoteImageLoader().comicPage(for: address, headers: [:], maxPixelSize: 4096)
        let decoded = try result.get()
        XCTAssertEqual(decoded.size.width, 320, accuracy: 1,
                       "The 4096-pixel longest-edge thumbnail must not blur a tall strip's text")
        XCTAssertEqual(decoded.size.height, 6000, accuracy: 1)
        XCTAssertLessThanOrEqual(decoded.size.width * decoded.size.height, 8 * 1024 * 1024)
    }

    func testBitmapDecodeBudgetLeavesQueuedCancelledImagesUndecoded() async throws {
        let started = expectation(description: "two bitmap decoders")
        started.expectedFulfillmentCount = 2
        let release = DispatchSemaphore(value: 0)
        let workers = (0..<2).map { _ in
            Task {
                await RemoteImageLoader.decodeBitmap {
                    XCTAssertFalse(Thread.isMainThread)
                    started.fulfill()
                    XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
                    return nil
                }
            }
        }
        defer { release.signal(); release.signal(); workers.forEach { $0.cancel() } }
        await fulfillment(of: [started], timeout: 3)
        let cancelled = Task {
            await RemoteImageLoader.decodeBitmap {
                XCTFail("A queued cancelled bitmap must never consume a decoder")
                return nil
            }
        }
        cancelled.cancel()
        _ = await cancelled.value
        release.signal(); release.signal()
        for worker in workers { _ = await worker.value }
        let resumed = await RemoteImageLoader.decodeBitmap { UIImage() }
        XCTAssertNotNil(resumed, "All decoder permits must be returned after cancellation")
    }

    func testOrdinaryIllustrationsDoNotReuseBitmapsAcrossRequestHeaders() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ComicImageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let loader = RemoteImageLoader(session: session)
        let address = try XCTUnwrap(URL(string: "https://comic-image-fixture.invalid/context.png"))
        ComicImageURLProtocol.setSuccess(true)
        let authorized = ["Referer": "https://comic.example/chapter/1"]
        for size: CGFloat? in [nil, 80] {
            let allowed = await loader.image(for: address, headers: authorized, maxPixelSize: size)
            XCTAssertNotNil(allowed)
            let rejected = await loader.image(for: address, headers: [:], maxPixelSize: size)
            XCTAssertNil(rejected, "A cached authorized illustration must not satisfy another request context")
        }
    }

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
        XCTAssertNotNil(loader.cachedImage(for: url, headers: ["Referer": "https://comic.example/chapter/1"]))
        XCTAssertNil(loader.cachedImage(for: url))
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

    func testRepeatedChapterCancellationReleasesAllFourPermitsForTheNextChapter() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeldComicImageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let loader = RemoteImageLoader(session: session)
        for chapter in 0..<3 {
            let urls = try (0..<7).map { page in
                try XCTUnwrap(URL(string: "https://held-comic.invalid/\(UUID().uuidString)/\(chapter)/\(page)"))
            }
            let readers = urls.map { url in
                Task { await loader.comicPage(for: url, headers: [:], maxPixelSize: 4096) }
            }
            defer { readers.forEach { $0.cancel() } }
            for _ in 0..<200 {
                if urls.reduce(0, { $0 + HeldComicImageURLProtocol.counts($1).started }) == 4 { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertEqual(urls.reduce(0) { $0 + HeldComicImageURLProtocol.counts($1).started }, 4,
                           "Chapter \(chapter) must acquire all four permits after its predecessor was cancelled")
            let waiting = urls.indices.filter { HeldComicImageURLProtocol.counts(urls[$0]).started == 0 }
            for index in waiting { readers[index].cancel() }
            for index in waiting { _ = await readers[index].value }
            loader.clearCache()
            for reader in readers {
                guard case .failure(.cancelled) = await reader.value else {
                    return XCTFail("A discarded chapter must finish without a decoded page")
                }
            }
            for _ in 0..<200 {
                if urls.allSatisfy({ let counts = HeldComicImageURLProtocol.counts($0); return counts.started == counts.stopped }) { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            for url in urls {
                let counts = HeldComicImageURLProtocol.counts(url)
                XCTAssertEqual(counts.started, counts.stopped, "No transport may outlive its chapter")
                XCTAssertEqual(loader.comicSubscriberCount(for: url, headers: [:], maxPixelSize: 4096), 0)
                XCTAssertNil(loader.cachedComicPage(for: url, headers: [:], maxPixelSize: 4096))
            }
        }
    }
}

/// Advertises an oversized body or streams one without ever sending EOF.
private final class OversizedComicImageURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var stopped = Set<URL>()

    static func hasStopped(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped.contains(url)
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "oversized-comic.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let isDeclared = url.path.hasPrefix("/declared/")
        let limit = ComicOfflineArchive.maximumPageBytes
        var headers = ["Content-Type": "image/png"]
        if isDeclared { headers["Content-Length"] = String(limit + 1) }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        guard !isDeclared else { return }
        let chunk = Data(repeating: 0, count: 1024 * 1024)
        for _ in 0...(limit / chunk.count) {
            client?.urlProtocol(self, didLoad: chunk)
        }
    }

    override func stopLoading() {
        guard let url = request.url else { return }
        Self.lock.lock()
        Self.stopped.insert(url)
        Self.lock.unlock()
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
