import XCTest

final class RootTabGlassUITests: XCTestCase {
    func testRealHomeRetainsOneFloatingBarAndSearchInBothAppearances() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        let coverURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "jianlai-cover", withExtension: "jpg"))
        app.launchEnvironment["SOURCEREAD_UI_COVER_JPEG"] = try Data(contentsOf: coverURL).base64EncodedString()
        for mode in ["light", "dark"] {
            app.launchArguments = ["--floating-desk-regression", "-settings.themeMode", mode,
                "-settings.visualTheme", "pineMist", "-settings.readingDeskEnabled", "YES"]
            app.launch()
            let search = app.buttons["bookshelf.globalSearch"]
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            for identifier in ["tabs.legacy.home", "tabs.legacy.discover", "tabs.legacy.settings"] {
                let matches = app.buttons.matching(identifier: identifier)
                XCTAssertEqual(matches.count, 1)
                XCTAssertTrue(matches.firstMatch.isHittable)
            }
            XCTAssertTrue(search.isHittable)
            XCTAssertGreaterThanOrEqual(search.frame.width, 44)
            let home = app.buttons["tabs.legacy.home"]
            let settings = app.buttons["tabs.legacy.settings"]
            XCTAssertLessThan(settings.frame.maxX, search.frame.minX)
            XCTAssertEqual(home.frame.midY, search.frame.midY, accuracy: 4)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "root-tab-glass-real-home-pineMist-" + mode
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }
}
