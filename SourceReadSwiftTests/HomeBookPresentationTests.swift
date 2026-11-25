import XCTest
@testable import SourceReadSwift

final class HomeBookPresentationTests: XCTestCase {
    func testMenuUsesReferenceOrderAndKeepsCurrentDeskOutOfPicker() {
        XCTAssertEqual(HomeBookPresentation.allCases.map(\.rawValue),
            ["showcase", "journal", "classic", "shelfRow"])
        XCTAssertFalse(HomeBookPresentation.allCases.contains(.current))
    }

    func testClassicIsFreshDefaultAndInvalidStoredValuesKeepLegacyFallback() {
        XCTAssertEqual(HomeBookPresentation.initialSelection, .classic)
        XCTAssertEqual(HomeBookPresentation.resolve("unknown-presentation"), .classic)
        XCTAssertEqual(HomeBookPresentation.resolve(""), .classic)
        XCTAssertEqual(HomeBookPresentation.resolve("current"), .current)
        XCTAssertEqual(HomeBookPresentation.resolve("shelfRow"), .shelfRow)
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

    func testBootstrapSelectsClassicOnceAndPreservesEverySavedPresentation() throws {
        let suite = "home-book-presentation-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        HomeBookPresentation.bootstrapSelection(in: defaults)
        XCTAssertEqual(defaults.string(forKey: HomeBookPresentation.storageKey), "classic")
        HomeBookPresentation.bootstrapSelection(in: defaults)
        XCTAssertEqual(defaults.string(forKey: HomeBookPresentation.storageKey), "classic")

        for rawValue in ["current", "showcase", "journal", "classic", "shelfRow", "sculptural", "magazine", "library"] {
            defaults.set(rawValue, forKey: HomeBookPresentation.storageKey)
            HomeBookPresentation.bootstrapSelection(in: defaults)
            HomeBookPresentation.bootstrapSelection(in: defaults)
            XCTAssertEqual(defaults.string(forKey: HomeBookPresentation.storageKey), rawValue)
        }
    }
}
