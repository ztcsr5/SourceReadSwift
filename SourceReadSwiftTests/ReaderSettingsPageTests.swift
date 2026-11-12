import XCTest
@testable import SourceReadSwift

/// Verifies the Settings-tab typography page writes exactly the keys the reader
/// observes, and that those values survive `ReaderBindingPreferences` validation
/// (which is what guards backup import and saved bindings).
final class ReaderSettingsPageTests: XCTestCase {
    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "reader-settings-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    func testEveryAppearanceKeyIsCoveredByTheDeclaredFormGroups() {
        let grouped = ReaderBindingPreferences.bodyKeys
            + ReaderBindingPreferences.headingKeys
            + ReaderBindingPreferences.chromeKeys
            + ReaderBindingPreferences.surfaceKeys
        XCTAssertEqual(Set(grouped), Set(ReaderBindingPreferences.appearanceKeys))
        XCTAssertEqual(grouped.count, Set(grouped).count, "A key must belong to exactly one form group")
        // 这七个键也属于「外观」，但各有自己的编辑器（阅读器内页眉页脚编辑、字体管理、
        // 壁纸深浅色适配），放进这个表单会写出和真实运行状态冲突的值：
        // 例如 statusPosition 由 ReaderChromeEditor 改，customBackgroundIsDark 由壁纸采样改。
        let ownedElsewhere: Set<String> = [
            "reader.showSystemStatusBar", "reader.statusPosition",
            "reader.allowsDuplicateTopStatus", "reader.contentExtendsIntoChrome",
            "reader.customFontPostScriptName", "reader.customBackgroundIsDark",
            "reader.customBackgroundIsDarkManual"
        ]
        XCTAssertTrue(Set(ReaderBindingPreferences.appearanceKeys)
                        .isSubset(of: Set(ReaderBindingPreferences.defaults.keys)),
                      "The form may only write keys the validator knows")
        XCTAssertEqual(Set(ReaderBindingPreferences.defaults.keys)
                        .subtracting(ReaderBindingPreferences.appearanceKeys), ownedElsewhere,
                       "Any appearance key left out of this form must have another owner")
    }

    func testClampKeepsFormValuesInsideTheValidatorRanges() {
        XCTAssertEqual(ReaderBindingPreferences.clamp(200, forKey: "reader.fontSize"), 60)
        XCTAssertEqual(ReaderBindingPreferences.clamp(1, forKey: "reader.fontSize"), 12)
        XCTAssertEqual(ReaderBindingPreferences.clamp(0.1, forKey: "reader.headerOpacity"), 0.35)
        XCTAssertEqual(ReaderBindingPreferences.clamp(.nan, forKey: "reader.fontSize"), 12)
        XCTAssertEqual(ReaderBindingPreferences.clamp(3.5, forKey: "reader.unranged"), 3.5)
    }

    func testWritingFormValuesThroughDefaultsRoundTripsThroughTheValidator() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Exactly what the form writes through @AppStorage.
        defaults.set(ReaderFontFamily.songti.rawValue, forKey: "reader.fontFamily")
        defaults.set(24.0, forKey: "reader.fontSize")
        defaults.set(12.0, forKey: "reader.lineSpacing")
        defaults.set(1.5, forKey: "reader.letterSpacing")
        defaults.set(20.0, forKey: "reader.paragraphSpacing")
        defaults.set(48.0, forKey: "reader.paragraphIndent")
        defaults.set(28.0, forKey: "reader.pagePadding")
        defaults.set(ReaderPageChromeLayout.inline.rawValue, forKey: "reader.chapterHeadingStyle")
        defaults.set(ReaderFontFamily.kaiti.rawValue, forKey: "reader.chapterTitleFamily")
        defaults.set(true, forKey: "reader.chapterTitleBold")
        defaults.set(0.0, forKey: "reader.chapterTitleSize")
        defaults.set(16.0, forKey: "reader.titleSpacing")
        defaults.set(ReaderChapterDecoration.branch.rawValue, forKey: "reader.chapterDecoration")
        defaults.set(ReaderChapterAlignment.center.rawValue, forKey: "reader.chapterAlignment")
        defaults.set(14.0, forKey: "reader.headerFontSize")
        defaults.set(6.0, forKey: "reader.headerTopGap")
        defaults.set(0.6, forKey: "reader.headerOpacity")
        defaults.set(96.0, forKey: "reader.footerHeight")
        defaults.set(false, forKey: "reader.footerShowTime")
        defaults.set(true, forKey: "reader.footerShowBatteryIcon")
        defaults.set(false, forKey: "reader.footerShowBatteryPercent")
        defaults.set(ReaderBackground.bamboo.rawValue, forKey: "reader.background")
        defaults.set(ReaderWallpaperFillMode.fit.rawValue, forKey: "reader.customWallpaperFillMode")
        defaults.set("paper", forKey: "reader.menuSurfaceStyle")
        defaults.set(true, forKey: "reader.menuUsesWallpaper")
        defaults.set(0.9, forKey: "reader.menuPaperOpacity")

        let captured = try ReaderBindingPreferences.capture(defaults)
        XCTAssertEqual(captured.text("reader.fontFamily"), ReaderFontFamily.songti.rawValue)
        XCTAssertEqual(captured.text("reader.background"), ReaderBackground.bamboo.rawValue)
        XCTAssertEqual(captured.text("reader.chapterDecoration"), ReaderChapterDecoration.branch.rawValue)
        XCTAssertEqual(captured.text("reader.chapterHeadingStyle"), ReaderPageChromeLayout.inline.rawValue)
    }

    func testRestoringDefaultsClearsEveryAppearanceKeyBackToItsFactoryValue() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(52.0, forKey: "reader.fontSize")
        defaults.set(ReaderBackground.dark.rawValue, forKey: "reader.background")
        defaults.set("paper", forKey: "reader.menuSurfaceStyle")

        for key in ReaderBindingPreferences.appearanceKeys {
            if let fallback = ReaderBindingPreferences.defaults[key] {
                defaults.set(fallback.propertyListValue, forKey: key)
            }
        }
        defaults.set(UUID().uuidString, forKey: "reader.bindingRevision")

        let captured = try ReaderBindingPreferences.capture(defaults)
        for key in ReaderBindingPreferences.appearanceKeys {
            XCTAssertEqual(captured.values[key], ReaderBindingPreferences.defaults[key], key)
        }
        XCTAssertNotNil(defaults.string(forKey: "reader.bindingRevision"))
    }

    func testRestoringDefaultsDoesNotTouchProgressOrReadingMode() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(712, forKey: "reader.currentParagraphIndex")
        defaults.set("pageCurl", forKey: "reader.mode")
        defaults.set("keep-me", forKey: "reader.bookID")

        for key in ReaderBindingPreferences.appearanceKeys {
            if let fallback = ReaderBindingPreferences.defaults[key] {
                defaults.set(fallback.propertyListValue, forKey: key)
            }
        }

        XCTAssertEqual(defaults.integer(forKey: "reader.currentParagraphIndex"), 712)
        XCTAssertEqual(defaults.string(forKey: "reader.mode"), "pageCurl")
        XCTAssertEqual(defaults.string(forKey: "reader.bookID"), "keep-me")
    }
}
