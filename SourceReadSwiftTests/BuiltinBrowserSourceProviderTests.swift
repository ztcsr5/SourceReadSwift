import XCTest
@testable import SourceReadSwift

final class BuiltinBrowserSourceProviderTests: XCTestCase {

    func testBuiltinBrowserSourceProvider() {
        let source = BuiltinBrowserSourceProvider.defaultBrowserSource

        XCTAssertEqual(source.bookSourceUrl, "$BROWSER_SOURCE$")
        XCTAssertTrue(source.enabled)
        XCTAssertEqual(source.bookSourceType, 0)
        XCTAssertNotNil(source.ruleBookInfo)
        XCTAssertNotNil(source.ruleToc)
        XCTAssertNotNil(source.ruleContent)

        // Verify book info heuristics
        XCTAssertNotNil(source.ruleBookInfo?.fields["name"])
        XCTAssertNotNil(source.ruleBookInfo?.fields["author"])
        XCTAssertNotNil(source.ruleBookInfo?.fields["tocUrl"])

        // Verify content heuristics
        XCTAssertNotNil(source.ruleContent?.fields["content"])
        XCTAssertNotNil(source.ruleContent?.fields["replaceRegex"])

        // Test URL identification
        XCTAssertTrue(BuiltinBrowserSourceProvider.isBrowserSource(url: "$BROWSER_SOURCE$"))
        XCTAssertTrue(BuiltinBrowserSourceProvider.isBrowserSource(url: "$BROWSER_SOURCE$#custom"))
        XCTAssertFalse(BuiltinBrowserSourceProvider.isBrowserSource(url: "https://example.com"))
    }
}
