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

    func testMissingCoverReturnsNil() {
        XCTAssertNil(CoverURLResolver.url(from: nil, base: "https://example.com"))
        XCTAssertNil(CoverURLResolver.url(from: "   ", base: "https://example.com"))
        XCTAssertNil(CoverURLResolver.url(from: "a.jpg", base: nil, fallbackBase: nil))
    }
}
