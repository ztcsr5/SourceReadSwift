import Foundation
import XCTest
@testable import SourceReadSwift

final class ComicImageCookieBoundaryTests: XCTestCase {
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
        let loader = RemoteImageLoader(configuration: defaultConfiguration())
        let signedInURL = server.rootURL.appendingPathComponent("signed-in.png")
        let anonymousURL = server.rootURL.appendingPathComponent("anonymous.png")
        let loggedOutURL = server.rootURL.appendingPathComponent("logged-out.png")
        let signedIn = await SourceImageRequestHeaders.addingSessionCookies(
            to: ComicImageRequest(url: signedInURL.absoluteString, headers: [:]), engine: first)
        _ = try await loader.comicBytesForArchive(signedIn).get()
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
