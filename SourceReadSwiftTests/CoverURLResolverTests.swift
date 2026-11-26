import XCTest
@testable import SourceReadSwift

final class CoverURLResolverTests: XCTestCase {
    func testAbsoluteCoverIsKept() {
        let url = CoverURLResolver.url(
            from: "https://cdn.example.com/a.jpg",
            base: "https://example.com/book/1",
            fallbackBase: "https://example.com"
        )
        XCTAssertEqual(url?.absoluteString, "https://cdn.example.com/a.jpg")
    }

    func testProtocolRelativeCoverUsesHTTPS() {
        let url = CoverURLResolver.url(
            from: "//cdn.example.com/a.jpg",
            base: nil,
            fallbackBase: nil
        )
        XCTAssertEqual(url?.absoluteString, "https://cdn.example.com/a.jpg")
    }

    func testRootRelativeCoverUsesBookURL() {
        let url = CoverURLResolver.url(
            from: "/images/a.jpg",
            base: "https://example.com/book/1",
            fallbackBase: "https://example.com"
        )
        XCTAssertEqual(url?.absoluteString, "https://example.com/images/a.jpg")
    }

    func testRelativeBookURLIsResolvedAgainstSourceHome() {
        let url = CoverURLResolver.url(
            from: "images/a.jpg",
            base: "/book/1",
            fallbackBase: "https://example.com"
        )
        XCTAssertEqual(url?.absoluteString, "https://example.com/book/images/a.jpg")
    }

    func testCoverRefererUsesSourceOriginWithoutBookSecrets() throws {
        let cover = try XCTUnwrap(URL(string: "https://images.example/cover.jpg"))
        let headers = CoverURLResolver.requestHeaders(for: cover,
            base: "https://books.example/book/123?ticket=private#reading",
            fallbackBase: "https://user:password@source.example:8443/catalog?token=private#section")
        XCTAssertEqual(headers, ["Referer": "https://source.example:8443/"])
    }

    func testCoverRefererCanFallBackToBookOrigin() throws {
        let cover = try XCTUnwrap(URL(string: "https://images.example/cover.jpg"))
        XCTAssertEqual(CoverURLResolver.requestHeaders(for: cover, base: "https://books.example/book/123?ticket=private"),
                       ["Referer": "https://books.example/"])
        XCTAssertEqual(CoverURLResolver.requestHeaders(for: cover, base: nil, fallbackBase: "//source.example/path"),
                       ["Referer": "https://source.example/"])
    }

    func testLocalCoverAndInsecureDowngradeDoNotSendReferer() throws {
        for address in ["file:///tmp/cover.jpg", "data:image/png;base64,AA==", "http://images.example/cover.jpg"] {
            let cover = try XCTUnwrap(URL(string: address))
            XCTAssertTrue(CoverURLResolver.requestHeaders(for: cover, base: "https://books.example/book/1").isEmpty, address)
        }
        let cover = try XCTUnwrap(URL(string: "https://images.example/cover.jpg"))
        XCTAssertTrue(CoverURLResolver.requestHeaders(for: cover, base: nil).isEmpty)
        XCTAssertTrue(CoverURLResolver.requestHeaders(for: cover, base: "local://comic").isEmpty)
    }

    func testMissingCoverReturnsNil() {
        XCTAssertNil(CoverURLResolver.url(from: nil, base: "https://example.com"))
        XCTAssertNil(CoverURLResolver.url(from: "   ", base: "https://example.com"))
        XCTAssertNil(CoverURLResolver.url(from: "a.jpg", base: nil, fallbackBase: nil))
    }
}
