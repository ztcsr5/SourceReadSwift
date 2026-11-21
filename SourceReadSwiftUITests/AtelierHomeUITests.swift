import XCTest

final class AtelierHomeUITests: XCTestCase {
    func testSixBookPresentationsKeepUnclippedBooksAndOpenRealProse() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        for presentation in ["classic", "showcase", "journal", "sculptural", "magazine", "library"] {
            try launch(app, theme: "paper", presentation: presentation)
            let entry = currentBook(app, title: "剑来")
            if presentation == "magazine" || presentation == "library" {
                let shelf = app.scrollViews["home.books.horizontalShelf"].firstMatch
                XCTAssertTrue(shelf.exists)
                XCTAssertGreaterThanOrEqual(entry.frame.width, 44)
                XCTAssertGreaterThan(entry.frame.height, presentation == "magazine" ? 160 : 134)
                XCTAssertGreaterThanOrEqual(entry.frame.minY, shelf.frame.minY - 1)
                XCTAssertLessThanOrEqual(entry.frame.maxY, shelf.frame.maxY + 1,
                                        "The horizontal viewport must include the complete book and caption")
            }
            capture(app, name: "home-presentation-" + presentation + "-light")
            entry.tap()
            let prose = app.webViews.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "这是纸间的隔离视觉验证书库")).firstMatch
            XCTAssertTrue(prose.waitForExistence(timeout: 15), presentation + " must open the real reader")
            app.terminate()
        }
    }

    func testSevenThemesKeepTheActualHomeAndSearchReachable() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        for theme in ["forest", "classic", "kleinSage", "shuimo", "wuxia", "anime", "kawaii"] {
            try launch(app, theme: theme)
            let current = currentBook(app, title: "剑来")
            let maxCardHeight: CGFloat = (theme == "forest" || theme == "kleinSage") ? 266 : 380
            XCTAssertLessThanOrEqual(current.frame.height, maxCardHeight, theme)
            let search = searchButton(app)
            XCTAssertTrue(search.isHittable, theme)
            XCTAssertTrue(tab(app, title: "主页", legacyID: "tabs.legacy.home").exists, theme)
            capture(app, name: "atelier-home-" + theme + "-light")
            app.terminate()
        }
    }

    func testPineMistPagerKeepsItsShelfStillAcrossShortAndLongTitles() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        try launch(app, theme: "shuimo")
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

    private func launch(_ app: XCUIApplication, theme: String, presentation: String = "classic") throws {
        let cover = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "jianlai-cover", withExtension: "jpg"))
        app.launchEnvironment["SOURCEREAD_UI_COVER_JPEG"] = try Data(contentsOf: cover).base64EncodedString()
        app.launchArguments = ["--floating-desk-regression", "-settings.themeMode", "light",
            "-settings.visualTheme", theme, "-settings.readingDeskEnabled", "YES", "-settings.reducesMotion", "NO",
            "-settings.homeBookPresentation", presentation, "-reader.mode", "scroll"]
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
