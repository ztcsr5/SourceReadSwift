import XCTest
@testable import SourceReadSwift

final class SourceLoginURLResolverTests: XCTestCase {
    func testAbsoluteLoginURL() {
        let target = SourceLoginURLResolver.resolve(
            loginUrl: "https://example.com/login",
            bookSourceUrl: "https://example.com"
        )
        XCTAssertEqual(target?.url.absoluteString, "https://example.com/login")
        XCTAssertEqual(target?.usedBookSourceFallback, false)
    }

    func testRelativeLoginURLUsesBookSourceBase() {
        let target = SourceLoginURLResolver.resolve(
            loginUrl: "/user/login.php",
            bookSourceUrl: "https://example.com/book/index.html"
        )
        XCTAssertEqual(target?.url.absoluteString, "https://example.com/user/login.php")
        XCTAssertEqual(target?.usedBookSourceFallback, false)
    }

    func testEmptyLoginURLFallsBackToHomePage() {
        let target = SourceLoginURLResolver.resolve(
            loginUrl: "",
            bookSourceUrl: "https://example.com"
        )
        XCTAssertEqual(target?.url.absoluteString, "https://example.com")
        XCTAssertEqual(target?.usedBookSourceFallback, true)
    }

    func testTemplateLoginURLExpandsBookSourceAlias() {
        let target = SourceLoginURLResolver.resolve(
            loginUrl: "{{bookSourceUrl}}/login",
            bookSourceUrl: "https://example.com"
        )
        XCTAssertEqual(target?.url.absoluteString, "https://example.com/login")
        XCTAssertEqual(target?.usedBookSourceFallback, false)
    }

    func testProtocolRelativeLoginURLUsesHTTPS() {
        let target = SourceLoginURLResolver.resolve(
            loginUrl: "//example.com/signin",
            bookSourceUrl: "https://example.com"
        )
        XCTAssertEqual(target?.url.absoluteString, "https://example.com/signin")
    }

    func testRelativePathWithoutLeadingSlashUsesBookSourceBase() {
        let target = SourceLoginURLResolver.resolve(
            loginUrl: "user/login",
            bookSourceUrl: "https://example.com/book/index.html"
        )
        XCTAssertEqual(target?.url.absoluteString, "https://example.com/book/user/login")
        XCTAssertEqual(target?.usedBookSourceFallback, false)
    }

    func testMissingEverythingReturnsNil() {
        XCTAssertNil(SourceLoginURLResolver.resolve(loginUrl: nil, bookSourceUrl: nil))
        XCTAssertNil(SourceLoginURLResolver.resolve(loginUrl: "  ", bookSourceUrl: ""))
    }
}
