import SwiftUI
import XCTest
@testable import SourceReadSwift

final class ForestBrandThemeTests: XCTestCase {
    func testThemeFamiliesKeepExistingKeysAndDistinctIllustratedBackgrounds() {
        let classic = AppVisualTheme.classicDeskThemes
        let floating = AppVisualTheme.floatingBookThemes
        XCTAssertEqual(classic.first, .classic)
        XCTAssertEqual(floating.first, .forest)
        XCTAssertEqual(Set(classic + floating), Set(AppVisualTheme.allCases))
        XCTAssertEqual(classic.count + floating.count, AppVisualTheme.allCases.count)
        XCTAssertNil(AppVisualTheme.forest.illustratedPaper)
        XCTAssertEqual(AppVisualTheme.inkwash.illustratedPaper?.wallpaperAssetName, "ReadingMountains")
        let atmosphericAssets = AppVisualTheme.atmosphericThemes.flatMap {
            [$0.atmosphericPaperAsset(isDark: false), $0.atmosphericPaperAsset(isDark: true)].compactMap { $0 }
        }
        XCTAssertEqual(Set(atmosphericAssets).count, 8)
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
                let accentKey = theme.preferenceKey("accent")
                defaults.set("123456", forKey: accentKey)
                defaults.set("ABCDEF", forKey: accentKey + ".dark")
                AppVisualTheme.bootstrapSelection(in: defaults)
                XCTAssertEqual(AppVisualTheme.selected(in: defaults), theme)
                XCTAssertEqual(defaults.string(forKey: accentKey), "123456")
                XCTAssertEqual(defaults.string(forKey: accentKey + ".dark"), "ABCDEF")
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

    @MainActor func testForestPaletteUsesWhiteCanvasAndNeutralSurfaces() {
        let forest = AppVisualTheme.forest
        XCTAssertEqual(forest.backgroundHex, 0xFFFFFF)
        XCTAssertEqual(forest.cardHex, 0xFFFFFF)
        XCTAssertEqual(forest.darkBackgroundHex, 0x151716)
        XCTAssertEqual(forest.darkCardHex, 0x222423)
        XCTAssertEqual(forest.accentHex, 0x3D6348)
        XCTAssertEqual(forest.darkAccentHex, 0xBAD6C0)
        XCTAssertEqual(forest.borderWidth, 0)

        let paper = AppVisualTheme.paper
        XCTAssertEqual(paper.backgroundHex, 0xF4F4F4)
        XCTAssertEqual(paper.darkBackgroundHex, 0x000000)
        XCTAssertEqual(paper.darkCardHex, 0x161616)
        XCTAssertTrue(paper.usesNeutralGlass)

        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let colors: [(Color, String, String)] = [
            (forest.primaryInk, "1C211D", "F0F2EF"),
            (forest.secondaryInk, "626862", "ABB1AB"),
            (forest.controlFill, "F3F3F0", "303430"),
            (forest.controlBorder, "E6E8E3", "414641"),
        ]
        for (color, lightHex, darkHex) in colors {
            XCTAssertEqual(AppTheme.hex(Color(uiColor: UIColor(color).resolvedColor(with: light))), lightHex)
            XCTAssertEqual(AppTheme.hex(Color(uiColor: UIColor(color).resolvedColor(with: dark))), darkHex)
        }
        XCTAssertEqual(AppTheme.hex(Color(uiColor: UIColor(paper.primaryInk).resolvedColor(with: light))), "111111")
        XCTAssertEqual(AppTheme.hex(Color(uiColor: UIColor(paper.secondaryInk).resolvedColor(with: light))), "595959")
        XCTAssertEqual(AppTheme.hex(Color(uiColor: UIColor(paper.controlFill).resolvedColor(with: light))), "EDEDED")
        XCTAssertEqual(AppTheme.hex(Color(uiColor: UIColor(paper.controlBorder).resolvedColor(with: light))), "E6E6E6")

        let classic = AppVisualTheme.classic
        XCTAssertEqual(classic.accentHex, 0x594FDB)
        XCTAssertEqual(classic.backgroundHex, 0xF2F2F7)
        XCTAssertEqual(classic.selectionSurfaceHex, 0xF3F3F0)
        XCTAssertEqual(classic.neutralBorderHex, 0xE6E8E3)
    }

    @MainActor func testForestPrimaryActionUsesBlackAndWhiteInBothAppearances() {
        let defaults = UserDefaults.standard
        let savedTheme = defaults.object(forKey: AppVisualTheme.selectionKey)
        defer { defaults.set(savedTheme, forKey: AppVisualTheme.selectionKey) }
        defaults.set(AppVisualTheme.forest.rawValue, forKey: AppVisualTheme.selectionKey)

        for (style, fill, ink) in [(UIUserInterfaceStyle.light, "1C211D", "FFFFFF"),
                                   (.dark, "F0F2EF", "111111")] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            XCTAssertEqual(AppTheme.hex(Color(uiColor: UIColor(AppTheme.prominentFill).resolvedColor(with: traits))), fill)
            XCTAssertEqual(AppTheme.hex(Color(uiColor: UIColor(AppTheme.prominentInk).resolvedColor(with: traits))), ink)
        }
    }

    func testThemeCompositionsChangeShelfAndReadingHierarchyWithoutChangingTheDefaultHome() {
        XCTAssertEqual(AppVisualTheme.forest.homeComposition, .readingDesk)
        XCTAssertEqual(AppVisualTheme.classic.homeComposition, .readingDesk)
        XCTAssertEqual(AppVisualTheme.kleinSage.homeComposition, .editorial)
        XCTAssertEqual(AppVisualTheme.inkwash.homeComposition, .index)
        XCTAssertEqual(AppVisualTheme.anime.homeComposition, .gallery)
        XCTAssertEqual(Set(AppVisualTheme.allCases.map(\.homeComposition)), Set(AppVisualTheme.HomeComposition.allCases))
        XCTAssertEqual(AppVisualTheme.wuxia.surfaceRadius(preferred: 18), 6)
        XCTAssertEqual(AppVisualTheme.kleinSage.surfaceRadius(preferred: 18), 8)
        XCTAssertEqual(AppVisualTheme.wuxia.surfaceRadius(preferred: 999), 999)
        XCTAssertEqual(AppVisualTheme.forest.surfaceRadius(preferred: 24), 22)
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
