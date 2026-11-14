import XCTest
@testable import SourceReadSwift

final class Release117ReaderPersonalizationTests: XCTestCase {
    func testFourOriginalDoodlesPersistAndHaveDistinctCachedDayNightTiles() throws {
        let backgrounds: [ReaderBackground] = [.paperCats, .moonLetters, .cloudIslands, .starPlanes]
        XCTAssertEqual(try JSONDecoder().decode([ReaderBackground].self, from: JSONEncoder().encode(backgrounds)), backgrounds)
        var bitmaps = Set<Data>()
        for background in backgrounds {
            XCTAssertTrue(ReaderBackground.pickerCases.contains(background))
            XCTAssertTrue(background.hasTexture)
            XCTAssertNil(background.wallpaperAssetName, "Vector backgrounds need no remote or bundled bitmap")
            XCTAssertNotNil(background.doodlePattern)
            XCTAssertTrue(background.darkStatusIcon(isNight: false))
            XCTAssertFalse(background.darkStatusIcon(isNight: true))
            for night in [false, true] {
                let image = ReaderPaperTexture.image(background: background, night: night)
                XCTAssertTrue(image === ReaderPaperTexture.image(background: background, night: night))
                XCTAssertEqual(image.size.width, 256)
                XCTAssertEqual(image.size.height, 256)
                bitmaps.insert(try XCTUnwrap(image.pngData()))
                let attachment = XCTAttachment(image: image)
                attachment.name = "release117-doodle-\(background.rawValue)-\(night ? "night" : "day")"
                attachment.lifetime = .keepAlways; add(attachment)
            }
        }
        XCTAssertEqual(bitmaps.count, 8, "Every motif and appearance must have its own rendered result")
    }

    func testHistoricalReaderBackgroundRawValuesRemainDecodable() throws {
        let historical = ["paper", "kraftTexture", "parchmentTexture", "linen", "bamboo", "mountains", "ginkgo", "tide", "kraft", "green", "lavender", "azure", "white", "gray", "dark", "eink", "custom", "sakuraClassic", "sakuraDark", "sakuraSolarized", "sakuraEarthly", "sakuraInk", "sakuraVader"]
        let decoded = try JSONDecoder().decode([ReaderBackground].self, from: JSONEncoder().encode(historical))
        XCTAssertEqual(decoded.map(\.rawValue), historical)
        XCTAssertEqual(ReaderBackground.allCases.count, historical.count + 10)
    }

    func testCuratedPhase2BackgroundsHaveDayNightAssetsAndContrast() {
        for item in [ReaderBackground.sageGreen, .shuimoPaper, .wuxiaScroll, .starlight, .sakuraSky, .kawaiiNote] {
            XCTAssertTrue(ReaderBackground.pickerCases.contains(item))
            XCTAssertNotEqual(item.dayBackgroundHex, item.dayTextHex)
            XCTAssertNotEqual(item.nightBackgroundHex, item.nightTextHex)
        }
        XCTAssertTrue(ReaderBackground.shuimoPaper.hasDedicatedNightAsset)
        XCTAssertEqual(ReaderBackground.shuimoPaper.wallpaperAssetName(isNight: true), "ThemeShuimoNight")
        XCTAssertEqual(ReaderBackground.starlight.wallpaperAssetName(isNight: false), "ReadingStarlight")
        XCTAssertEqual(ReaderBackground.starlight.dayTextHex, 0xEDE6D6)
        XCTAssertEqual(ReaderBackground.starlight.resolvedTextHex(isNight: false, customInkHex: 0xABCDEF), 0xABCDEF)
    }

    func testTypographyAlignmentWeightAndVerticalPaddingAreBounded() {
        XCTAssertEqual(ReaderTextAlignment.smart.nsTextAlignment, .justified)
        XCTAssertTrue(ReaderTextAlignment.smart.compressesPunctuation)
        XCTAssertFalse(ReaderTextAlignment.justified.compressesPunctuation)
        XCTAssertEqual(ReaderTextAlignment.leading.cssTextAlign, "left")
        XCTAssertEqual(ReaderBodyFontWeight.semibold.cssWeight, 600)
        XCTAssertEqual(ReaderBodyFontWeight.light.cssWeight, 300)

        let baseline = ReaderPageGeometry(
            viewportSize: CGSize(width: 390, height: 844),
            safeTop: 47,
            safeBottom: 34,
            horizontalMargin: 20,
            verticalPadding: 0
        )
        let padded = ReaderPageGeometry(
            viewportSize: CGSize(width: 390, height: 844),
            safeTop: 47,
            safeBottom: 34,
            horizontalMargin: 20,
            verticalPadding: 16
        )
        XCTAssertEqual(padded.bodyTop - baseline.bodyTop, 16, accuracy: 0.5)
        XCTAssertLessThan(padded.contentHeight, baseline.contentHeight)
    }

    func testWallpaperAdjustmentLegacyDecodingAndValidationPreserveDefaults() throws {
        let legacyJSON = Data(#"{"zoom":1.2,"horizontalOffset":0.1,"verticalOffset":-0.2,"dimming":0.3,"fillMode":"fit","usesLightText":true}"#.utf8)
        var decoded = try JSONDecoder().decode(ReaderWallpaperAdjustment.self, from: legacyJSON)
        XCTAssertEqual(decoded.blurRadius, 0)
        XCTAssertEqual(decoded.grainOpacity, 0)
        XCTAssertEqual(decoded.nightDimming, 0.45, accuracy: 0.0001)
        XCTAssertNoThrow(try decoded.validate())

        decoded.blurRadius = 24
        decoded.grainOpacity = 0.35
        decoded.nightDimming = 0
        XCTAssertNoThrow(try decoded.validate())

        var invalid = decoded
        invalid.blurRadius = 99
        XCTAssertThrowsError(try invalid.validate())

        invalid = decoded
        invalid.grainOpacity = 2.0
        XCTAssertThrowsError(try invalid.validate())

        invalid = decoded
        invalid.nightDimming = -1
        XCTAssertThrowsError(try invalid.validate())
    }

    func testBookmarkExporterAndInBookSearchAndAmbientPresets() throws {
        let mark1 = ReaderBookmark(
            chapterIndex: 0,
            chapterTitle: "第一章 起风",
            paragraphIndex: 2,
            snippet: "山雨欲来风满楼。"
        )
        let md = BookmarkExporter.markdown(bookTitle: "测试书", author: "作者甲", bookmarks: [mark1])
        XCTAssertTrue(md.contains("# 《测试书》书签摘录"))
        XCTAssertTrue(md.contains("> 山雨欲来风满楼。"))
        let txt = BookmarkExporter.plainText(bookTitle: "测试书", author: "作者甲", bookmarks: [mark1])
        XCTAssertTrue(txt.contains("第 1 章 · 第 3 段"))

        let hits = ReaderInBookSearchEngine.search(
            query: "星辰",
            sources: [
                ReaderInBookSearchChapterSource(chapterIndex: 1, title: "二", paragraphs: ["月明星稀", "星辰大海在前方"]),
                ReaderInBookSearchChapterSource(chapterIndex: 0, title: "一", paragraphs: ["序言里的星辰"])
            ]
        )
        XCTAssertEqual(hits.map(\.chapterIndex), [0, 1])
        XCTAssertEqual(hits.map(\.paragraphIndex), [0, 1])

        XCTAssertEqual(ReaderAmbientPreset.recommended(for: .wuxia), .rain)
        XCTAssertEqual(ReaderAmbientPreset.recommended(for: .shuimo), .paperWind)
        XCTAssertEqual(ReaderAmbientPreset.recommended(for: .anime), .nightWave)
        XCTAssertEqual(ReaderAmbientPreset.recommended(for: .kawaii), .cafeWarmth)

        XCTAssertTrue(ReaderVolumeTurnPolicy.shouldIntercept(isEnabled: true, isSpeaking: false, isSheetPresented: false, isActive: true))
        XCTAssertFalse(ReaderVolumeTurnPolicy.shouldIntercept(isEnabled: true, isSpeaking: true, isSheetPresented: false, isActive: true))
        XCTAssertFalse(ReaderVolumeTurnPolicy.shouldIntercept(isEnabled: true, isSpeaking: false, isSheetPresented: true, isActive: true))
    }
}
