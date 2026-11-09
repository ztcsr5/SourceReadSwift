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
            let search = searchButton(app)
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            capture(app, name: "home-before-hit-test-" + mode)
            let home = tab(app, title: "主页", legacyID: "tabs.legacy.home")
            let discover = tab(app, title: "寻书", legacyID: "tabs.legacy.discover")
            let settings = tab(app, title: "设置", legacyID: "tabs.legacy.settings")
            for button in [home, discover, settings] {
                XCTAssertTrue(button.waitForExistence(timeout: 5))
                XCTAssertTrue(button.isHittable)
            }
            XCTAssertTrue(search.isHittable)
            XCTAssertGreaterThanOrEqual(search.frame.width, 44)
            XCTAssertLessThan(settings.frame.maxX, search.frame.minX)
            XCTAssertEqual(home.frame.midY, search.frame.midY, accuracy: 4)
            discover.tap()
            XCTAssertTrue(app.textFields["搜索书名或作者"].waitForExistence(timeout: 5))
            XCTAssertTrue(discover.isSelected)
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

    private func tab(_ app: XCUIApplication, title: String, legacyID: String) -> XCUIElement {
        let legacy = app.buttons[legacyID]
        if legacy.exists { return legacy }
        let native = app.tabBars.buttons[title]
        return native.exists ? native : app.buttons[title]
    }

    private func searchButton(_ app: XCUIApplication) -> XCUIElement {
        let legacy = app.buttons["bookshelf.globalSearch"]
        if legacy.exists { return legacy }
        let native = app.tabBars.buttons["全网搜书"]
        return native.exists ? native : app.buttons["全网搜书"]
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "root-tab-glass-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
