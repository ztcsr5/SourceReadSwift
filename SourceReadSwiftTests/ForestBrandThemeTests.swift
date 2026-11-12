import SwiftUI
import XCTest
@testable import SourceReadSwift

final class ForestBrandThemeTests: XCTestCase {
    func testThemeFamiliesKeepExistingKeysAndDistinctIllustratedBackgrounds() {
        let classic = AppVisualTheme.classicDeskThemes
        let floating = AppVisualTheme.floatingBookThemes
        XCTAssertEqual(classic.first, .classic)
        XCTAssertEqual(floating.first, .forest)
        let video = AppVisualTheme.videoGlassThemes
        XCTAssertEqual(Set(classic + floating + video), Set(AppVisualTheme.allCases))
        XCTAssertEqual(classic.count + floating.count + video.count, AppVisualTheme.allCases.count)
        XCTAssertTrue(video.allSatisfy(\.isVideoGlass))
        XCTAssertFalse(floating.contains(where: \.isVideoGlass))
        XCTAssertFalse(classic.contains(where: \.isVideoGlass))
        XCTAssertNil(AppVisualTheme.forest.illustratedPaper)
        let assets = floating.compactMap { $0.illustratedPaper?.wallpaperAssetName }
        XCTAssertEqual(Set(assets).count, 4)
    }

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
        XCTAssertEqual(AppVisualTheme.forest.accentHex, 0x3D6348)
        XCTAssertEqual(AppVisualTheme.forest.selectionSurfaceHex, 0xF3F3F0)
        XCTAssertEqual(AppVisualTheme.forest.neutralBorderHex, 0xE6E8E3)
        XCTAssertEqual(AppVisualTheme.classic.accentHex, 0x594FDB)
        XCTAssertEqual(AppVisualTheme.classic.backgroundHex, 0xF2F2F7)
    }

    func testThemeCompositionsChangeShelfAndReadingHierarchyWithoutChangingTheDefaultHome() {
        XCTAssertEqual(AppVisualTheme.forest.homeComposition, .readingDesk)
        XCTAssertEqual(AppVisualTheme.classic.homeComposition, .readingDesk)
        XCTAssertEqual(AppVisualTheme.editorial.homeComposition, .editorial)
        XCTAssertEqual(AppVisualTheme.blueprint.homeComposition, .index)
        XCTAssertEqual(AppVisualTheme.folio.homeComposition, .gallery)
        XCTAssertEqual(Set(AppVisualTheme.allCases.map(\.homeComposition)), Set(AppVisualTheme.HomeComposition.allCases))
        XCTAssertEqual(AppVisualTheme.editorial.surfaceRadius(preferred: 18), 6)
        XCTAssertEqual(AppVisualTheme.blueprint.surfaceRadius(preferred: 18), 8)
        XCTAssertEqual(AppVisualTheme.editorial.surfaceRadius(preferred: 999), 999)
        XCTAssertEqual(AppVisualTheme.forest.surfaceRadius(preferred: 24), 24)
    }

    func testShelfJacketBoundsKeepTheRasterInsideTheSameTwoToThreeBook() {
        for (width, height) in [(CGFloat(52), CGFloat(72)), (80, 120), (58, 82)] {
            let size = ShelfCoverGeometry.size(maxWidth: width, height: height)
            XCTAssertLessThanOrEqual(size.width, width)
            XCTAssertLessThanOrEqual(size.height, height)
            XCTAssertEqual(size.width / size.height, 2.0 / 3.0, accuracy: 0.0001)
        }
        XCTAssertEqual(ShelfCoverGeometry.size(maxWidth: nil, height: 120), CGSize(width: 80, height: 120))
    }

    private func withDefaults(_ run: (UserDefaults) -> Void) throws {
        let suite = "forest-brand-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        run(defaults)
    }
}
