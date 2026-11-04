import SwiftUI
import XCTest
@testable import SourceReadSwift

final class ForestBrandThemeTests: XCTestCase {
    func testFreshInstallDefaultsToForestWithoutChangingAfterWelcomeSeed() throws {
        try withDefaults { defaults in
            AppVisualTheme.bootstrapSelection(in: defaults)
            XCTAssertEqual(AppVisualTheme.selected(in: defaults), .forest)
            defaults.set(true, forKey: BookshelfStore.welcomeSeedPreferenceKey)
            AppVisualTheme.bootstrapSelection(in: defaults)
            XCTAssertEqual(AppVisualTheme.selected(in: defaults), .forest)
        }
    }

    func testUpgradePreservesSavedThemesAndLegacyCustomPalette() throws {
        try withDefaults { defaults in
            for theme in AppVisualTheme.allCases {
                defaults.set(theme.rawValue, forKey: AppVisualTheme.selectionKey)
                AppVisualTheme.bootstrapSelection(in: defaults)
                XCTAssertEqual(AppVisualTheme.selected(in: defaults), theme)
            }
            defaults.removeObject(forKey: AppVisualTheme.selectionKey)
            defaults.set("123456", forKey: AppVisualTheme.classic.preferenceKey("accent"))
            AppVisualTheme.bootstrapSelection(in: defaults)
            XCTAssertEqual(AppVisualTheme.selected(in: defaults), .classic)
            XCTAssertEqual(defaults.string(forKey: "settings.accentHex"), "123456")
            XCTAssertNotEqual(AppVisualTheme.forest.preferenceKey("accent"), "settings.accentHex")
        }
    }

    func testLegacyInstallWithoutSelectionKeepsClassic() throws {
        try withDefaults { defaults in
            defaults.set(true, forKey: BookshelfStore.welcomeSeedPreferenceKey)
            AppVisualTheme.bootstrapSelection(in: defaults)
            XCTAssertEqual(AppVisualTheme.selected(in: defaults), .classic)
        }
    }

    func testForestPaletteUsesWhiteAndNeutralSurfaces() {
        XCTAssertEqual(AppVisualTheme.forest.backgroundHex, 0xFFFFFF)
        XCTAssertEqual(AppVisualTheme.forest.accentHex, 0x294631)
        XCTAssertEqual(AppVisualTheme.forest.selectionSurfaceHex, 0xF3F3F0)
        XCTAssertEqual(AppVisualTheme.forest.neutralBorderHex, 0xE6E8E3)
        XCTAssertEqual(AppVisualTheme.classic.accentHex, 0x594FDB)
        XCTAssertEqual(AppVisualTheme.classic.backgroundHex, 0xF2F2F7)
    }

    private func withDefaults(_ run: (UserDefaults) -> Void) throws {
        let suite = "forest-brand-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        run(defaults)
    }
}
