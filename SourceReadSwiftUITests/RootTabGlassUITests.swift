import XCTest

final class RootTabGlassUITests: XCTestCase {
    func testOldSystemLastSettingsRowClearsTheOnlyTabBar() throws {
        if #available(iOS 18, *) { throw XCTSkip("iOS 16/17 tab layout") }
        let app = XCUIApplication()
        app.launchArguments = ["--reader-preview-regression", "-settings.themeMode", "dark"]
        app.launch()
        let bar = app.tabBars.firstMatch
        let settings = bar.buttons["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        let about = app.buttons["settings.about"]
        for _ in 0..<7 where !about.isHittable || about.frame.maxY > bar.frame.minY { app.swipeUp() }
        XCTAssertEqual(app.tabBars.count, 1)
        XCTAssertFalse(app.buttons["tabs.legacy.settings"].exists)
        XCTAssertTrue(about.isHittable)
        XCTAssertLessThanOrEqual(about.frame.maxY, bar.frame.minY + 1)
        about.tap()
        XCTAssertTrue(app.navigationBars["关于纸间"].waitForExistence(timeout: 3))
        app.navigationBars["关于纸间"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 3))
        for title in ["主页", "寻书", "搜书", "设置"] {
            let item = bar.buttons[title]
            XCTAssertTrue(item.isHittable); item.tap()
            XCTAssertTrue(item.isSelected)
            XCTAssertEqual(app.tabBars.count, 1)
        }
    }

    func testRealHomeRetainsOneFloatingBarAndSearchInBothAppearances() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        let coverURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "jianlai-cover", withExtension: "jpg"))
        app.launchEnvironment["SOURCEREAD_UI_COVER_JPEG"] = try Data(contentsOf: coverURL).base64EncodedString()
        for mode in ["light", "dark"] {
            app.launchArguments = ["--floating-desk-regression", "-settings.themeMode", mode,
                "-settings.visualTheme", "shuimo", "-settings.readingDeskEnabled", "YES"]
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
            XCTAssertTrue(app.navigationBars["寻书"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.searchFields.count, 0)
            XCTAssertFalse(app.segmentedControls["discover.matchMode"].exists)
            XCTAssertTrue(discover.isSelected)
            capture(app, name: "discover-after-tab-tap-" + mode)
            settings.tap()
            XCTAssertTrue(app.buttons["外观"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(settings.isSelected)
            home.tap()
            let shelf = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bookshelf.continue.")).firstMatch
            XCTAssertTrue(shelf.waitForExistence(timeout: 5))
            XCTAssertTrue(home.isSelected)
            capture(app, name: "real-home-shuimo-" + mode)
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
        let native = app.tabBars.buttons["搜书"]
        return native.exists ? native : app.buttons["搜书"]
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "root-tab-glass-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
