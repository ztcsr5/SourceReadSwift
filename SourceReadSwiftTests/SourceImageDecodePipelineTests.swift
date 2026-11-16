import XCTest
import UIKit
@testable import SourceReadSwift

final class SourceImageDecodePipelineTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAIAAAASFvFNAAAAGklEQVR42mNgYGhg0ADiACBmCACygTggoAEAMGgE4bJ9Q/wAAAAASUVORK5CYII=")!
    // AES-CBC of the first 32 PNG bytes, followed by its untouched tail and a fixture key.
    private let encrypted = Data(base64Encoded: "ADAwOTkSTXHKvsy12h3RjVKJ4OeblnfvU2LCP1WuySN8DO4AqqHN+qWQf55RGfkHEkLmQWhNAAAAGklEQVR42mNgYGhg0ADiACBmCACygTggoAEAMGgE4bJ9Q/wAAAAASUVORK5CYIIwMTIzNDU2Nzg5YWJjZGVm")!

    private let byteRule = """
    var length = Number(java.bytesToStr(result.slice(1, 5)));
    var key = result.slice(length + 5);
    var payload = result.slice(5, length + 5);
    var iv = src.split('?iv=')[1];
    var decoded = java.createSymmetricCrypto('AES/CBC/PKCS7Padding', key, iv).decrypt(payload.slice(0, 48));
    Buffer.concat([decoded, payload.slice(48)]);
    """

    func testDownloadedBytesReachByteHookBeforeImageDecodingAndCacheIsRuleScoped() async throws {
        let url = fixtureURL()
        ImageDecodeURLProtocol.register(encrypted, at: url)
        defer { ImageDecodeURLProtocol.remove(url) }
        let loader = makeLoader()
        let context = try XCTUnwrap(SourceImageDecodeContext(source: source(rule: byteRule), chapter: chapter()))
        let loaded = try await loader.comicPage(for: url, headers: [:], maxPixelSize: 4096, decodeContext: context).get()
        XCTAssertEqual(loaded.size.width, 3, accuracy: 0.01)
        XCTAssertEqual(loaded.size.height, 2, accuracy: 0.01)
        XCTAssertNotNil(loader.cachedComicPage(for: url, headers: [:], maxPixelSize: 4096, decodeContext: context))
        XCTAssertNil(loader.cachedComicPage(for: url, headers: [:], maxPixelSize: 4096))
        let changed = try XCTUnwrap(SourceImageDecodeContext(source: source(rule: "throw new Error('fixture failure')"), chapter: chapter()))
        XCTAssertNotEqual(context.fingerprint, changed.fingerprint)
        let changedResult = await loader.comicPage(for: url, headers: [:], maxPixelSize: 4096, decodeContext: changed)
        guard case .failure(.imageDecodeFailed) = changedResult else { return XCTFail("A changed hook must not reuse the preceding image") }
        XCTAssertEqual(ImageDecodeURLProtocol.requestCount(url), 2)
    }

    func testArchiveStoresDecodedImagesAndReopensWithoutTheRuleOrNetwork() async throws {
        let url = fixtureURL()
        ImageDecodeURLProtocol.register(encrypted, at: url)
        defer { ImageDecodeURLProtocol.remove(url) }
        let loader = makeLoader()
        let context = try XCTUnwrap(SourceImageDecodeContext(source: source(rule: byteRule), chapter: chapter()))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = ComicOfflineArchive(directory: root)
        let content = ChapterContent(chapter: chapter(), title: "Fixture", paragraphs: ["[img]\(url.absoluteString)[/img]"])
        try await archive.save(content, sourceURL: context.source.bookSourceUrl, headers: [:]) { request in
            var decodedRequest = request
            decodedRequest.decodeContext = context
            return await loader.comicBytesForArchive(decodedRequest)
        }
        ImageDecodeURLProtocol.remove(url)
        let reopened = ComicOfflineArchive(directory: root)
        let saved = await reopened.pages(sourceURL: context.source.bookSourceUrl, chapter: content.chapter)
        let page = try XCTUnwrap(saved?.first)
        let address = try XCTUnwrap(URL(string: page.url))
        XCTAssertEqual(try Data(contentsOf: address), png)
        let image = try await loader.comicPage(for: address, headers: [:], maxPixelSize: 4096).get()
        XCTAssertEqual(image.size.width, 3, accuracy: 0.01)
    }

    func testPlainJavaByteStreamHookNormalizesSignedOctets() async throws {
        let rule = """
        (function() {
          var input = new Packages.java.io.ByteArrayInputStream(result);
          var output = new Packages.java.io.ByteArrayOutputStream();
          var value;
          while ((value = input.read()) !== -1) output.write(value ^ 90);
          return output.toByteArray().map(function(byte) { return byte > 127 ? byte - 256 : byte; });
        })()
        """
        let context = try XCTUnwrap(SourceImageDecodeContext(source: source(rule: rule), chapter: chapter()))
        let masked = Data(png.map { $0 ^ 90 })
        let decoded = try await SourceImageByteDecoder.decode(masked, sourceURL: fixtureURL(), context: context).get()
        XCTAssertEqual(decoded, png)
    }

    func testWrappedByteHooksAreUnwrappedBeforeEvaluation() async throws {
        for wrapped in ["@js:" + byteRule, "<js>" + byteRule + "</js>"] {
            let context = try XCTUnwrap(SourceImageDecodeContext(source: source(rule: wrapped), chapter: chapter()))
            XCTAssertFalse(context.script.hasPrefix("@js:"))
            XCTAssertFalse(context.script.hasPrefix("<js>"))
            let decoded = try await SourceImageByteDecoder.decode(encrypted, sourceURL: fixtureURL(), context: context).get()
            XCTAssertEqual(decoded, png)
        }
    }

    func testChapterSessionSnapshotIsStableAndChangesItsCacheIdentityWithSourceSettings() async throws {
        let state = RulePersistentState()
        let rule = "var mask = Number(source.get('mask')); result.map(function(byte) { return byte ^ mask; });"
        state.put("90", for: "source.variable.mask")
        let first = try XCTUnwrap(SourceImageDecodeContext(source: source(rule: rule), chapter: chapter(), persistentState: state))
        state.put("91", for: "source.variable.mask")
        let next = try XCTUnwrap(SourceImageDecodeContext(source: source(rule: rule), chapter: chapter(), persistentState: state))
        XCTAssertNotEqual(first.fingerprint, next.fingerprint)
        XCTAssertEqual(first.sourceValues["source.variable.mask"], "90")
        let decoded = try await SourceImageByteDecoder.decode(Data(png.map { $0 ^ 90 }), sourceURL: fixtureURL(), context: first).get()
        XCTAssertEqual(decoded, png, "Already queued pages must retain the settings associated with their cache identity")
    }

    func testOversizedOutputAndInvalidByteValuesAreNotSilentlyTruncated() async throws {
        let oversized = try XCTUnwrap(SourceImageDecodeContext(
            source: source(rule: "new Uint8Array(\(ComicOfflineArchive.maximumPageBytes + 1));"), chapter: chapter()))
        let huge = await SourceImageByteDecoder.decode(png, sourceURL: fixtureURL(), context: oversized)
        guard case .failure(.tooLarge) = huge else { return XCTFail("Image output size must be checked before encoding") }
        let invalid = try XCTUnwrap(SourceImageDecodeContext(source: source(rule: "result[0] = 256; result;"), chapter: chapter()))
        let malformed = await SourceImageByteDecoder.decode(png, sourceURL: fixtureURL(), context: invalid)
        guard case .failure(.imageDecodeFailed) = malformed else { return XCTFail("Do not wrap an invalid byte into a different image") }
    }

    func testCancelledDecodeDoesNotEvaluateItsRule() async throws {
        let context = try XCTUnwrap(SourceImageDecodeContext(source: source(rule: "throw new Error('must not execute')"), chapter: chapter()))
        let bytes = png
        let url = fixtureURL()
        let task = Task {
            do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { }
            return await SourceImageByteDecoder.decode(bytes, sourceURL: url, context: context)
        }
        task.cancel()
        guard case .failure(.cancelled) = await task.value else { return XCTFail("Cancelled decode must stop before evaluating JavaScript") }
    }

    func testChapterParserLeavesByteHooksDeferredButPreservesLegacyURLRewrite() throws {
        let response = SourceResponse(url: URL(string: "https://source.invalid/chapter")!, statusCode: 200,
            headers: ["Content-Type": "application/json"], body: #"{"body":"[img]https://image.invalid/thumb/a.png[/img]"}"#, data: Data())
        let parser = ContentParser()
        let deferred = try parser.parse(source: source(rule: byteRule), chapter: chapter(), response: response).get()
        XCTAssertEqual(deferred.paragraphs, ["[img]https://image.invalid/thumb/a.png[/img]"])
        let rewritten = try parser.parse(source: source(rule: "<js>result.replace('/thumb/', '/large/');</js>"), chapter: chapter(), response: response).get()
        XCTAssertEqual(rewritten.paragraphs, ["[img]https://image.invalid/large/a.png[/img]"])
        XCTAssertTrue(SourceImageDecodeContext.needsDownloadedBytes("@js:result.slice(0);"))
        XCTAssertFalse(SourceImageDecodeContext.needsDownloadedBytes("##/thumb/##/large/##"))
    }

    private func source(rule: String) -> BookSource {
        BookSource(bookSourceName: "Byte fixture", bookSourceUrl: "https://source.invalid", bookSourceType: 2,
            ruleContent: SourceRule(fields: ["content": "$.body", "imageDecode": rule]))
    }

    private func chapter() -> BookChapter {
        BookChapter(title: "Fixture", url: "https://source.invalid/chapter", bookUrl: "https://source.invalid/book", index: 0)
    }

    private func fixtureURL() -> URL {
        URL(string: "https://image-byte-fixture.invalid/\(UUID().uuidString)?iv=fedcba9876543210")!
    }

    private func makeLoader() -> RemoteImageLoader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageDecodeURLProtocol.self]
        return RemoteImageLoader(configuration: configuration)
    }
}

private final class ImageDecodeURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var fixtures: [URL: Data] = [:]
    private static var requests: [URL: Int] = [:]

    static func register(_ bytes: Data, at url: URL) {
        lock.lock(); defer { lock.unlock() }
        fixtures[url] = bytes
        requests[url] = 0
    }

    static func remove(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        fixtures.removeValue(forKey: url)
        requests.removeValue(forKey: url)
    }

    static func requestCount(_ url: URL) -> Int {
        lock.lock(); defer { lock.unlock() }
        return requests[url, default: 0]
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "image-byte-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock()
        let bytes = Self.fixtures[url]
        Self.requests[url, default: 0] += 1
        Self.lock.unlock()
        guard let bytes, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/octet-stream", "Content-Length": String(bytes.count)]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bytes)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
