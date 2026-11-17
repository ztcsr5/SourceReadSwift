import Darwin
import Foundation
import XCTest
@testable import SourceReadSwift

final class ComicImageCookieBoundaryTests: XCTestCase {
    func testIdleFirstConnectionDoesNotBlockTheActualImageRequest() async throws {
        let server = try ComicCookieHTTPServer()
        server.start()
        defer { server.stop() }
        let idle = try openIdleConnection(to: server.rootURL)
        defer { Darwin.close(idle) }
        let accepted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            server.acceptedConnectionCount == 1
        }, object: nil)
        await fulfillment(of: [accepted], timeout: 2)
        let loader = RemoteImageLoader(configuration: defaultConfiguration())
        let address = server.rootURL.appendingPathComponent("after-idle.png")
        let result = await loader.comicBytesForArchive(ComicImageRequest(url: address.absoluteString, headers: [:]))
        guard case .success(let bytes) = result else {
            XCTFail("Image transfer failed while the first peer stayed idle: \(result); \(server.diagnostics)")
            return
        }
        XCTAssertEqual(bytes, ComicCookieHTTPServer.image)
        XCTAssertNotNil(server.request(at: address))
        XCTAssertGreaterThanOrEqual(server.acceptedConnectionCount, 2)
    }

    func testFoundationControlSendsSharedCookieButComicRequestDoesNot() async throws {
        let server = try ComicCookieHTTPServer()
        server.start()
        defer { server.stop() }
        let cookie = try seedSharedCookie(for: server.rootURL)
        defer { HTTPCookieStorage.shared.deleteCookie(cookie) }
        let configuration = defaultConfiguration()
        XCTAssertTrue(configuration.httpShouldSetCookies)
        XCTAssertTrue(configuration.httpCookieStorage === HTTPCookieStorage.shared)
        let control = URLSession(configuration: configuration)
        defer { control.invalidateAndCancel() }
        let controlURL = server.rootURL.appendingPathComponent("foundation.png")
        let (bytes, response) = try await control.data(for: URLRequest(url: controlURL))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(bytes, ComicCookieHTTPServer.image)
        XCTAssertEqual(try XCTUnwrap(server.request(at: controlURL)).cookie, "\(cookie.name)=\(cookie.value)")

        let loader = RemoteImageLoader(configuration: configuration)
        let imageURL = server.rootURL.appendingPathComponent("comic.png")
        let loaded = try await loader.comicBytesForArchive(ComicImageRequest(url: imageURL.absoluteString, headers: [:])).get()
        XCTAssertEqual(loaded, ComicCookieHTTPServer.image)
        XCTAssertNil(try XCTUnwrap(server.request(at: imageURL)).cookie,
                     "The source did not authorize Foundation's ambient cookie")
        XCTAssertNil(server.serverFailure)
    }

    func testExplicitSourcePageAndEmptyCookiesSurviveTheWireBoundary() async throws {
        let server = try ComicCookieHTTPServer()
        server.start()
        defer { server.stop() }
        let ambient = try seedSharedCookie(for: server.rootURL)
        defer { HTTPCookieStorage.shared.deleteCookie(ambient) }
        let source = BookSource(bookSourceName: "Cookie wire fixture", bookSourceUrl: server.rootURL.absoluteString,
            bookSourceType: 2, header: #"{"Cookie":"session=source"}"#)
        let chapter = makeChapter(server.rootURL)
        let addresses = ["source.png", "page.png", "empty.png"].map { server.rootURL.appendingPathComponent($0) }
        let resources = ComicChapterResources(offlinePages: [
            ComicPage(id: 0, url: addresses[0].absoluteString),
            ComicPage(id: 1, url: addresses[1].absoluteString, headers: ["cOoKiE": "session=page"]),
            ComicPage(id: 2, url: addresses[2].absoluteString, headers: ["cookie": ""])
        ])
        let engine = LegadoSourceEngine(cookieStore: SourceCookieStore(storageURL: nil),
            scriptCacheStore: SourceScriptCacheStore(isPersistent: false))
        let requests = try await ComicChapterRequestBuilder.build(resources: resources, source: source, chapter: chapter, engine: engine).get()
        let loader = RemoteImageLoader(configuration: defaultConfiguration())
        for request in requests {
            let loaded = try await loader.comicBytesForArchive(request).get()
            XCTAssertEqual(loaded, ComicCookieHTTPServer.image)
        }
        XCTAssertEqual(try XCTUnwrap(server.request(at: addresses[0])).cookie, "session=source")
        XCTAssertEqual(try XCTUnwrap(server.request(at: addresses[1])).cookie, "session=page")
        let empty = try XCTUnwrap(server.request(at: addresses[2])).cookie
        XCTAssertTrue(empty == nil || empty == "", "An explicitly empty Cookie must never re-enable the ambient jar")
    }

    func testAnonymousEngineAndLoggedOutEngineDoNotReceiveAmbientCookies() async throws {
        let server = try ComicCookieHTTPServer()
        server.start()
        defer { server.stop() }
        let ambient = try seedSharedCookie(for: server.rootURL)
        defer { HTTPCookieStorage.shared.deleteCookie(ambient) }
        let cookies = SourceCookieStore(storageURL: nil)
        await cookies.storeSetCookieHeaders(["Set-Cookie": "session=engine-a; Path=\(server.rootURL.path)"], for: server.rootURL)
        let first = LegadoSourceEngine(cookieStore: cookies, scriptCacheStore: SourceScriptCacheStore(isPersistent: false))
        let second = LegadoSourceEngine(cookieStore: SourceCookieStore(storageURL: nil),
            scriptCacheStore: SourceScriptCacheStore(isPersistent: false))
        let timeline = server.timeline
        timeline.record("loader-init")
        let loader = RemoteImageLoader(configuration: defaultConfiguration(), comicTransportObserver: { observation in
            let status = observation.httpStatusCode.map(String.init) ?? "none"
            let code = observation.errorCode.map(String.init) ?? "none"
            timeline.record("completed:status=\(status):bytes=\(observation.receivedBytes):error=\(code)")
        })
        let signedInURL = server.rootURL.appendingPathComponent("signed-in.png")
        let anonymousURL = server.rootURL.appendingPathComponent("anonymous.png")
        let loggedOutURL = server.rootURL.appendingPathComponent("logged-out.png")
        let signedIn = await SourceImageRequestHeaders.addingSessionCookies(
            to: ComicImageRequest(url: signedInURL.absoluteString, headers: [:]), engine: first)
        timeline.record("signed-in-load")
        let signedInResult = await loader.comicBytesForArchive(signedIn)
        timeline.record("signed-in-return")
        if ProcessInfo.processInfo.environment["SOURCE_READ_COMIC_DIAGNOSTICS"] == "1" {
            print("[DIAG-COOKIE-WIRE] \(server.diagnostics)")
        }
        guard case .success = signedInResult else {
            XCTFail("Signed-in image transport failed before Cookie assertions: \(signedInResult); \(server.diagnostics)")
            return
        }
        XCTAssertEqual(try XCTUnwrap(server.request(at: signedInURL)).cookie, "session=engine-a")
        let anonymous = await SourceImageRequestHeaders.addingSessionCookies(
            to: ComicImageRequest(url: anonymousURL.absoluteString, headers: [:]), engine: second)
        _ = try await loader.comicBytesForArchive(anonymous).get()
        XCTAssertNil(try XCTUnwrap(server.request(at: anonymousURL)).cookie)
        await cookies.clearCookies(matching: server.rootURL)
        let loggedOut = await SourceImageRequestHeaders.addingSessionCookies(
            to: ComicImageRequest(url: loggedOutURL.absoluteString, headers: [:]), engine: first)
        _ = try await loader.comicBytesForArchive(loggedOut).get()
        XCTAssertNil(try XCTUnwrap(server.request(at: loggedOutURL)).cookie,
                     "Deleting engine cookies must not expose an older Foundation session")
    }

    func testComicResponseDoesNotWriteSessionCookiesIntoTheSharedJar() async throws {
        let name = "comic_response_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let server = try ComicCookieHTTPServer(responseCookieName: name)
        server.start()
        defer {
            server.stop()
            for cookie in HTTPCookieStorage.shared.cookies ?? [] where cookie.name == name {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        let loader = RemoteImageLoader(configuration: defaultConfiguration())
        let imageURL = server.rootURL.appendingPathComponent("comic.png")
        for (path, headers) in [("comic.png", [String: String]()), ("explicit.png", ["Cookie": "session=explicit"])] {
            let address = server.rootURL.appendingPathComponent(path)
            _ = try await loader.comicBytesForArchive(ComicImageRequest(url: address.absoluteString, headers: headers)).get()
            XCTAssertFalse((HTTPCookieStorage.shared.cookies(for: address) ?? []).contains { $0.name == name },
                           "A comic response must not create credentials for unrelated engines")
        }

        let control = URLSession(configuration: defaultConfiguration())
        defer { control.invalidateAndCancel() }
        _ = try await control.data(for: URLRequest(url: server.rootURL.appendingPathComponent("control.png")))
        XCTAssertTrue((HTTPCookieStorage.shared.cookies(for: imageURL) ?? []).contains { $0.name == name },
                      "The control must prove that this HTTP response is a valid automatic cookie setter")
    }

    private func defaultConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = []
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        configuration.urlCache = nil
        return configuration
    }

    private func openIdleConnection(to url: URL) throws -> Int32 {
        let port = try XCTUnwrap(url.port)
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var address = sockaddr_in()
        address.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = UInt16(port).bigEndian
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        return descriptor
    }

    private func seedSharedCookie(for url: URL) throws -> HTTPCookie {
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .name: "ambient_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            .value: "synthetic-shared-session", .domain: "127.0.0.1", .path: url.path
        ]))
        HTTPCookieStorage.shared.setCookie(cookie)
        return cookie
    }

    private func makeChapter(_ root: URL) -> BookChapter {
        BookChapter(title: "Cookie boundary", url: root.appendingPathComponent("chapter").absoluteString,
            bookUrl: root.appendingPathComponent("book").absoluteString, index: 0)
    }
}
