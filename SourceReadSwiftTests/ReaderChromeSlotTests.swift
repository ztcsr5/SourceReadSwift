import XCTest
@testable import SourceReadSwift

final class ReaderChromeSlotTests: XCTestCase {
    func testEffectiveHeaderSlotsFallsBackToStatusOnlyWhenRightSlotIsNone() {
        let topStatusFallback = ReaderChromeSlotPolicy.effectiveHeaderSlots(
            left: .chapterTitle,
            center: .none,
            right: .none,
            statusPosition: "top",
            showTime: true,
            showBatteryIcon: true,
            showBatteryPercent: true
        )
        XCTAssertEqual(topStatusFallback.left, .chapterTitle)
        XCTAssertEqual(topStatusFallback.center, .none)
        XCTAssertEqual(topStatusFallback.right, .timeAndBattery)

        let explicitRight = ReaderChromeSlotPolicy.effectiveHeaderSlots(
            left: .bookTitle,
            center: .chapterTitle,
            right: .percentProgress,
            statusPosition: "both",
            showTime: true,
            showBatteryIcon: true,
            showBatteryPercent: false
        )
        XCTAssertEqual(explicitRight.left, .bookTitle)
        XCTAssertEqual(explicitRight.center, .chapterTitle)
        XCTAssertEqual(explicitRight.right, .percentProgress)

        let timeOnly = ReaderChromeSlotPolicy.effectiveHeaderSlots(
            left: .none,
            center: .none,
            right: .none,
            statusPosition: "both",
            showTime: true,
            showBatteryIcon: false,
            showBatteryPercent: false
        )
        XCTAssertEqual(timeOnly.right, .time)
    }

    func testHasVisibleFooterContentAndReservedHeightRespondToSlotsAndStatusPosition() {
        XCTAssertFalse(
            ReaderChromeSlotPolicy.hasVisibleFooterContent(
                left: .none,
                center: .none,
                right: .none,
                statusPosition: "top"
            )
        )
        XCTAssertEqual(
            ReaderPageChrome.scrollFooterReservedHeight(
                statusPosition: "top",
                leftSlot: .none,
                centerSlot: .none,
                rightSlot: .none
            ),
            0
        )

        XCTAssertTrue(
            ReaderChromeSlotPolicy.hasVisibleFooterContent(
                left: .none,
                center: .chapterAndPercent,
                right: .none,
                statusPosition: "top"
            )
        )
        XCTAssertEqual(
            ReaderPageChrome.scrollFooterReservedHeight(
                statusPosition: "top",
                leftSlot: .none,
                centerSlot: .chapterAndPercent,
                rightSlot: .none
            ),
            ReaderPageChrome.scrollFooterBandHeight
        )
    }

    func testScrollChromePolicyShowsHeaderWhenCenterOrRightOrBookTitleIsAssigned() {
        XCTAssertFalse(
            ReaderScrollChromePolicy.headerVisible(
                chapterStyle: .hidden,
                statusPosition: "bottom",
                leftSlot: .chapterTitle,
                centerSlot: .none,
                rightSlot: .none
            )
        )
        XCTAssertTrue(
            ReaderScrollChromePolicy.headerVisible(
                chapterStyle: .hidden,
                statusPosition: "bottom",
                leftSlot: .bookTitle,
                centerSlot: .none,
                rightSlot: .none
            )
        )
        XCTAssertTrue(
            ReaderScrollChromePolicy.headerVisible(
                chapterStyle: .hidden,
                statusPosition: "bottom",
                leftSlot: .none,
                centerSlot: .chapterTitle,
                rightSlot: .none
            )
        )
        XCTAssertTrue(
            ReaderScrollChromePolicy.headerVisible(
                chapterStyle: .hidden,
                statusPosition: "bottom",
                leftSlot: .none,
                centerSlot: .none,
                rightSlot: .percentProgress
            )
        )
    }

    func testBindingPreferencesIncludeAndValidateThreeSlotChromeKeys() throws {
        let suite = "ReaderChromeSlotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        for (key, value) in ReaderBindingPreferences.defaults {
            defaults.set(value.propertyListValue, forKey: key)
        }

        let captured = try ReaderBindingPreferences.capture(defaults)
        XCTAssertEqual(captured.text("reader.headerLeftSlot"), ReaderChromeSlotContent.chapterTitle.rawValue)
        XCTAssertEqual(captured.text("reader.footerRightSlot"), ReaderChromeSlotContent.pageAndBattery.rawValue)

        defaults.set("invalidSlotName", forKey: "reader.footerCenterSlot")
        XCTAssertThrowsError(try ReaderBindingPreferences.capture(defaults))
    }
}
