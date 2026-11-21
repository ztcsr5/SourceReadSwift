import XCTest
@testable import SourceReadSwift

final class HomeBookPresentationTests: XCTestCase {
    func testMenuUsesReferenceOrderAndKeepsCurrentDeskOutOfPicker() {
        XCTAssertEqual(HomeBookPresentation.allCases.map(\.rawValue),
            ["showcase", "journal", "classic", "sculptural", "magazine", "library"])
        XCTAssertFalse(HomeBookPresentation.allCases.contains(.current))
    }

    func testClassicIsDefaultAndInvalidStoredValuesFallBackWithoutBreakingLegacyValue() {
        XCTAssertEqual(HomeBookPresentation.initialSelection, .classic)
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

    @MainActor func testSpinesKeepUnicodeTitlesVerticalAndBoundLongTitles() {
        XCTAssertEqual(HomeBookSpine.titleLines(for: "剑来"), "剑\n来")
        XCTAssertEqual(HomeBookSpine.titleLines(for: "📚A"), "📚\nA")
        XCTAssertEqual(HomeBookSpine.titleLines(for: ""), "未\n命\n名\n书\n籍")
        let title = "白昼之后我们把很长很长的信写给远方"
        let lines = HomeBookSpine.titleLines(for: title).split(separator: "\n")
        XCTAssertEqual(lines.count, 10)
        XCTAssertEqual(lines.last, "…")
        XCTAssertEqual(lines.dropLast().joined(), String(title.prefix(9)))
    }
}
