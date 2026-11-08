import XCTest

final class AtelierHomeUITests: XCTestCase {
    func testSevenThemesKeepTheActualHomeAndSearchReachable() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        for theme in ["berryLake", "blushInk", "periwinkleCocoa", "peachMoss", "inkViolet", "pineMist", "kleinSage"] {
            try launch(app, theme: theme)
            let current = currentBook(app, title: "剑来")
            XCTAssertLessThanOrEqual(current.frame.height, 266, theme)
            let search = app.buttons["bookshelf.globalSearch"]
            XCTAssertTrue(search.isHittable, theme)
            XCTAssertEqual(app.buttons.matching(identifier: "tabs.legacy.home").count, 1)
            capture(app, name: "atelier-home-" + theme + "-light")
            app.terminate()
        }
    }

    func testPineMistPagerKeepsItsShelfStillAcrossShortAndLongTitles() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        try launch(app, theme: "pineMist")
        currentBook(app, title: "剑来")
        let filters = app.buttons["bookshelf.filters"]
        XCTAssertTrue(filters.waitForExistence(timeout: 5))
        let originalY = filters.frame.midY
        let pager = app.scrollViews["bookshelf.readingPager"].firstMatch
        XCTAssertTrue(pager.isHittable)
        pager.swipeLeft()
        currentBook(app, title: "月亮与六便士")
        XCTAssertEqual(filters.frame.midY, originalY, accuracy: 2)
        pager.swipeLeft()
        currentBook(app, title: "白昼之后")
        XCTAssertEqual(filters.frame.midY, originalY, accuracy: 2)
        capture(app, name: "atelier-home-pineMist-long-title")
    }

    private func launch(_ app: XCUIApplication, theme: String) throws {
        let cover = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "jianlai-cover", withExtension: "jpg"))
        app.launchEnvironment["SOURCEREAD_UI_COVER_JPEG"] = try Data(contentsOf: cover).base64EncodedString()
        app.launchArguments = ["--floating-desk-regression", "-settings.themeMode", "light",
            "-settings.visualTheme", theme, "-settings.readingDeskEnabled", "YES", "-settings.reducesMotion", "NO"]
        app.launch()
    }

    @discardableResult private func currentBook(_ app: XCUIApplication, title: String) -> XCUIElement {
        let book = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "bookshelf.continue.", title)).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 8))
        XCTAssertTrue(book.isHittable)
        return book
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
