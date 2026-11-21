import XCTest
@testable import SourceReadSwift

final class HomeBookPresentationTests: XCTestCase {
    func testMenuUsesReferenceOrderAndKeepsCurrentDeskOutOfPicker() {
        XCTAssertEqual(HomeBookPresentation.allCases.map(\.rawValue),
            ["showcase", "journal", "classic"])
        XCTAssertFalse(HomeBookPresentation.allCases.contains(.current))
    }

    func testShowcaseIsFreshDefaultAndInvalidStoredValuesKeepLegacyFallback() {
        XCTAssertEqual(HomeBookPresentation.initialSelection, .showcase)
        XCTAssertEqual(HomeBookPresentation.resolve("unknown-presentation"), .classic)
        XCTAssertEqual(HomeBookPresentation.resolve(""), .classic)
        XCTAssertEqual(HomeBookPresentation.resolve("current"), .current)
    }

    func testClassicAndLegacyCurrentReuseTheOriginalReadingDesk() {
        XCTAssertTrue(HomeBookPresentation.classic.usesClassicDesk)
        XCTAssertTrue(HomeBookPresentation.resolve("current").usesClassicDesk)
        for presentation in HomeBookPresentation.allCases where presentation != .classic {
            XCTAssertFalse(presentation.usesClassicDesk, presentation.rawValue)
        }
    }

    func testRetiredModesFallBackToClassicWithoutRejectingOldBackupValues() {
        for rawValue in ["sculptural", "magazine", "library"] {
            XCTAssertNotNil(HomeBookPresentation(rawValue: rawValue))
            XCTAssertEqual(HomeBookPresentation.resolve(rawValue), .classic)
            XCTAssertFalse(HomeBookPresentation.allCases.contains { $0.rawValue == rawValue })
        }
    }
}
