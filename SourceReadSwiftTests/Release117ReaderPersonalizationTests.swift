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
        XCTAssertEqual(ReaderBackground.allCases.count, historical.count + 4)
    }
}
