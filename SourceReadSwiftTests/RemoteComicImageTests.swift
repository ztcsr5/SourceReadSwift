import XCTest
import UIKit
@testable import SourceReadSwift

final class RemoteComicImageTests: XCTestCase {
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
        let code = ok && authorized ? 200 : 403
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAIAAAASFvFNAAAAGklEQVR42mNgYGhg0ADiACBmCACygTggoAEAMGgE4bJ9Q/wAAAAASUVORK5CYII=")!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: code == 200 ? data : Data("forbidden".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
