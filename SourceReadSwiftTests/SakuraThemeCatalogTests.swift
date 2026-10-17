import XCTest
@testable import SourceReadSwift

final class SakuraThemeCatalogTests: XCTestCase {

    func testSakuraThemeCatalog() {
        for theme in SakuraThemeCatalog.Theme.allCases {
            let css = SakuraThemeCatalog.css(for: theme)
            XCTAssertFalse(css.isEmpty)
            XCTAssertTrue(css.contains("normalize.css"))
            XCTAssertFalse(theme.displayName.isEmpty)
        }

        XCTAssertTrue(SakuraThemeCatalog.sakuraCSS.contains("body"))
        XCTAssertTrue(SakuraThemeCatalog.sakuraDarkCSS.contains("body"))
    }
}
