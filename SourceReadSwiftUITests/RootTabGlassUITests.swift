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
            capture(app, name: "home-before-hit-test-" + mode)
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
            app.buttons["tabs.legacy.discover"].tap()
            XCTAssertTrue(app.textFields["搜索书名或作者"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["tabs.legacy.discover"].isSelected)
            capture(app, name: "discover-after-tab-tap-" + mode)
            settings.tap()
            XCTAssertTrue(app.buttons["外观"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(settings.isSelected)
            home.tap()
            let shelf = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bookshelf.continue.")).firstMatch
            XCTAssertTrue(shelf.waitForExistence(timeout: 5))
            XCTAssertTrue(home.isSelected)
            capture(app, name: "real-home-pineMist-" + mode)
            app.terminate()
        }
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "root-tab-glass-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
