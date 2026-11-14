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
        let legacyJSON = Data(#"{"scale":1.2,"offsetX":0.1,"offsetY":-0.2,"dimming":0.3,"fillMode":"fit","usesLightText":true}"#.utf8)
        var decoded = try JSONDecoder().decode(ReaderWallpaperAdjustment.self, from: legacyJSON)
        XCTAssertEqual(decoded.blurRadius, 0)
        XCTAssertEqual(decoded.grainOpacity, 0)
        XCTAssertEqual(decoded.nightDimming, 0.55)

        decoded.blurRadius = 99
        decoded.grainOpacity = 2.0
        decoded.nightDimming = -1
        let clamped = decoded.validate()
        XCTAssertEqual(clamped.blurRadius, 24)
        XCTAssertEqual(clamped.grainOpacity, 0.35)
        XCTAssertEqual(clamped.nightDimming, 0)
    }
}
