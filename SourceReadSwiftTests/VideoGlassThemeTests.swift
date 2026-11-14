import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

final class VideoGlassThemeTests: XCTestCase {
    func testAtmosphericThemeAssetsDecodeInLightAndDarkVariants() throws {
        let requiredAssets = [
            "ThemeShuimoDay", "ThemeShuimoNight",
            "ThemeWuxiaDay", "ThemeWuxiaNight",
            "ThemeAnimeDay", "ThemeAnimeNight",
            "ThemeKawaiiDay", "ThemeKawaiiNight",
            "ReadingStarlight"
        ]
        for name in requiredAssets {
            let image = try XCTUnwrap(UIImage(named: name), "Missing bundled asset: \(name)")
            XCTAssertGreaterThan(image.size.height, image.size.width, "\(name) should be portrait-oriented")
        }
        for theme in AppVisualTheme.atmosphericThemes {
            XCTAssertNotNil(theme.atmosphericPaperAsset(isDark: false))
            XCTAssertNotNil(theme.atmosphericPaperAsset(isDark: true))
            XCTAssertNotEqual(theme.atmosphericPaperAsset(isDark: false), theme.atmosphericPaperAsset(isDark: true))
            XCTAssertNotEqual(theme.backgroundHex, theme.darkBackgroundHex)
            XCTAssertNotEqual(theme.cardHex, theme.darkCardHex)
        }
    }

    func testLegacyRemovedThemesMigrateSafelyAndDecoupleHomeComposition() throws {
        let suite = "phase1-theme-migration." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let legacyIDs = [
            "botanical", "editorial", "coast", "rose", "graphite", "folio", "blueprint",
            "berryLake", "blushInk", "periwinkleCocoa", "peachMoss", "inkViolet", "pineMist",
            "videoAurora", "videoEmber"
        ]
        for legacy in legacyIDs {
            XCTAssertEqual(AppVisualTheme.migrated(from: legacy), .classic)
            defaults.set(legacy, forKey: AppVisualTheme.selectionKey)
            XCTAssertEqual(AppVisualTheme.selected(in: defaults), .classic)
            AppVisualTheme.bootstrapSelection(in: defaults)
            XCTAssertEqual(defaults.string(forKey: AppVisualTheme.selectionKey), AppVisualTheme.classic.rawValue)
        }

        defaults.set(AppVisualTheme.forest.rawValue, forKey: AppVisualTheme.selectionKey)
        defaults.set(AppVisualTheme.HomeComposition.gallery.rawValue, forKey: HomeCompositionPreference.storageKey)
        XCTAssertEqual(AppVisualTheme.forest.resolvedHomeComposition(in: defaults), .gallery)
        defaults.set(HomeCompositionPreference.autoRawValue, forKey: HomeCompositionPreference.storageKey)
        XCTAssertNil(HomeCompositionPreference.selectedComposition(in: defaults))
        XCTAssertEqual(AppVisualTheme.forest.resolvedHomeComposition(in: defaults), .readingDesk)
    }

    @MainActor func testDualSyncAppIconAssetsAndThemeRecommendationsExist() throws {
        for option in AppIconOption.allCases {
            XCTAssertNotNil(UIImage(named: option.brandMarkAssetName), "Missing BrandMark asset \(option.brandMarkAssetName)")
            if option == .forest {
                XCTAssertNil(option.uiKitIconName)
            } else {
                XCTAssertEqual(option.uiKitIconName, option.rawValue)
            }
        }
        XCTAssertEqual(AppIconOption.recommended(for: .shuimo), .shuimo)
        XCTAssertEqual(AppIconOption.recommended(for: .wuxia), .wuxia)
        XCTAssertEqual(AppIconOption.recommended(for: .anime), .anime)
        XCTAssertEqual(AppIconOption.recommended(for: .kawaii), .kawaii)
        XCTAssertEqual(ThemeMode.system.uiUserInterfaceStyle, .unspecified)
        XCTAssertEqual(ThemeMode.light.uiUserInterfaceStyle, .light)
        XCTAssertEqual(ThemeMode.dark.uiUserInterfaceStyle, .dark)
        XCTAssertEqual(ThemeMode.pickerCases, [.system, .light, .dark])
    }

    @MainActor func testAppBrandChangesOnlyWhenTheSystemIconChanges() async throws {
        let suite = "AppIconManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var active: String? = AppIconOption.shuimo.rawValue
        var shouldFail = true
        let manager = AppIconManager(defaults: defaults, systemIcon: .init(
            isSupported: { true }, currentName: { active }, setName: { name in
                if shouldFail { throw CocoaError(.userCancelled) }
                active = name
            }))
        XCTAssertEqual(manager.currentOption, .shuimo)
        let failed = await manager.select(.wuxia)
        XCTAssertFalse(failed)
        XCTAssertEqual(manager.currentOption, .shuimo)
        XCTAssertEqual(AppIconOption.resolvedBrandAssetName(in: defaults), "BrandMarkShuimo")
        XCTAssertNotNil(manager.statusMessage)

        shouldFail = false
        let reset = await manager.select(.forest)
        XCTAssertTrue(reset)
        XCTAssertNil(active)
        XCTAssertEqual(manager.currentOption, .forest)
        XCTAssertEqual(AppIconOption.resolvedBrandAssetName(in: defaults), "BrandMark")
        XCTAssertNil(manager.statusMessage)
    }

    @MainActor func testCustomThemeStoreAndPaletteExtractionProduceReadableContrast() throws {
        let extracted = CustomThemePaletteExtractor.extractHarmoniousPalette(from: UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { ctx in
            UIColor(red: 0.14, green: 0.38, blue: 0.62, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        })
        XCTAssertNotEqual(extracted.lightCardHex, extracted.darkCardHex)
        XCTAssertNotEqual(extracted.lightAccentHex, extracted.darkAccentHex)
        let store = AppCustomThemeStore.shared
        XCTAssertFalse(store.presets.isEmpty)
        XCTAssertEqual(store.activePreset.id, store.activePresetID)
    }
}
