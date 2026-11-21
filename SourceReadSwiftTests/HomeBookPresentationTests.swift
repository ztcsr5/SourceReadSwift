import XCTest
@testable import SourceReadSwift

final class HomeBookPresentationTests: XCTestCase {
    func testMenuUsesReferenceOrderAndKeepsCurrentDeskOutOfPicker() {
        XCTAssertEqual(HomeBookPresentation.allCases.map(\.rawValue),
            ["showcase", "journal", "classic", "sculptural", "magazine", "library"])
        XCTAssertFalse(HomeBookPresentation.allCases.contains(.current))
    }

    func testShowcaseIsDefaultAndInvalidStoredValuesFallBackWithoutBreakingLegacyValue() {
        XCTAssertEqual(HomeBookPresentation.initialSelection, .showcase)
        XCTAssertEqual(HomeBookPresentation.resolve("unknown-presentation"), .showcase)
        XCTAssertEqual(HomeBookPresentation.resolve(""), .showcase)
        XCTAssertEqual(HomeBookPresentation.resolve("current"), .current)
    }
}
