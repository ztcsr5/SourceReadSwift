import XCTest

final class AtelierHomeUITests: XCTestCase {
    func testCoverGlassRemainsSharedAcrossHomeFindSettingsAndSearch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        try launch(app, theme: "coverGlass", presentation: "showcase")
        currentBook(app, title: "剑来")
        capture(app, name: "cover-glass-home")
        tab(app, title: "寻书", legacyID: "tabs.legacy.discover").tap()
        XCTAssertTrue(app.navigationBars["寻书"].waitForExistence(timeout: 5))
        capture(app, name: "cover-glass-find")
        tab(app, title: "设置", legacyID: "tabs.legacy.settings").tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        capture(app, name: "cover-glass-settings")
        searchButton(app).tap()
        XCTAssertTrue(app.navigationBars["搜书"].waitForExistence(timeout: 5))
        capture(app, name: "cover-glass-search")
    }

    func testThreeBookPresentationsOpenRealProse() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        for presentation in ["classic", "showcase", "journal"] {
            try launch(app, theme: "paper", presentation: presentation)
            let entry = currentBook(app, title: "剑来")
            capture(app, name: "home-presentation-" + presentation + "-light")
            entry.tap()
            let prose = app.webViews.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "这是纸间的隔离视觉验证书库")).firstMatch
            XCTAssertTrue(prose.waitForExistence(timeout: 15), presentation + " must open the real reader")
            app.terminate()
        }
    }

    func testHomeToolbarCanChangeBookPresentation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        try launch(app, theme: "forest", presentation: nil)
        let selector = app.descendants(matching: .any)
            .matching(identifier: "home.bookPresentation").firstMatch
        XCTAssertTrue(selector.waitForExistence(timeout: 5))
        selector.tap()
        let showcase = app.descendants(matching: .any)
            .matching(identifier: "home.bookPresentation.option.showcase").firstMatch
        XCTAssertTrue(showcase.waitForExistence(timeout: 5))
        showcase.tap()
        XCTAssertTrue(app.scrollViews["home.books.carousel"].waitForExistence(timeout: 5))
        capture(app, name: "home-toolbar-presentation-showcase")
        selector.tap()
        let classic = app.descendants(matching: .any)
            .matching(identifier: "home.bookPresentation.option.classic").firstMatch
        XCTAssertTrue(classic.waitForExistence(timeout: 5))
        classic.tap()
        XCTAssertTrue(app.scrollViews["bookshelf.readingPager"].waitForExistence(timeout: 5))
        capture(app, name: "home-toolbar-presentation-classic")
    }

    func testHomeChromeRemainsReachableAfterScrollingAllThreeModes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        for presentation in ["classic", "showcase", "journal"] {
            try launch(app, theme: "paper", presentation: presentation, hasLongShelf: true)
            currentBook(app, title: "剑来")
            for _ in 0..<3 { app.swipeUp() }
            let homeBar = app.navigationBars["主页"]
            XCTAssertTrue(homeBar.exists && homeBar.isHittable, presentation)
            XCTAssertTrue(tab(app, title: "主页", legacyID: "tabs.legacy.home").isHittable)
            if #available(iOS 26, *) {
                // Reverse browsing restores the native bar after its requested scroll minimization.
                app.swipeDown()
            }
            XCTAssertTrue(tab(app, title: "设置", legacyID: "tabs.legacy.settings").isHittable)
            XCTAssertTrue(searchButton(app).isHittable)
            capture(app, name: "home-stable-chrome-" + presentation)
            tab(app, title: "设置", legacyID: "tabs.legacy.settings").tap()
            XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
            tab(app, title: "主页", legacyID: "tabs.legacy.home").tap()
            XCTAssertTrue(homeBar.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testShowcaseKeepsTheNextCoverVisibleBeforeDragging() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        try launch(app, theme: "paper", presentation: "showcase")
        let lead = currentBook(app, title: "剑来")
        let next = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "bookshelf.continue.", "月亮与六便士")).firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        let viewport = app.scrollViews["home.books.carousel"].firstMatch
        XCTAssertTrue(viewport.exists)
        XCTAssertGreaterThan(next.frame.intersection(viewport.frame).width, 8)
        XCTAssertGreaterThan(lead.frame.width / lead.frame.height, 0.75)
        capture(app, name: "home-showcase-connected-covers")
    }

    func testOptionalShelfRowKeepsPreviewReadingAndLibrarySeparate() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        try launch(app, theme: "forest", presentation: "shelfRow")
        XCTAssertTrue(app.staticTexts["手边的书"].waitForExistence(timeout: 8))
        let title = app.staticTexts["home.shelfRow.title"]
        XCTAssertEqual(title.label, "剑来")
        let library = app.buttons["home.shelfRow.library"]
        XCTAssertTrue(library.isHittable)
        XCTAssertFalse(app.buttons["bookshelf.filters"].exists)
        let preview = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@",
            "home.shelfRow.preview.", "月亮与六便士")).firstMatch
        XCTAssertTrue(preview.isHittable)
        preview.tap()
        XCTAssertEqual(title.label, "月亮与六便士")
        let firstBook = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@",
            "home.shelfRow.preview.", "剑来")).firstMatch
        XCTAssertTrue(firstBook.isHittable)
        firstBook.tap()
        let resume = app.buttons["home.shelfRow.continue"]
        XCTAssertTrue(resume.isHittable)
        capture(app, name: "home-shelf-row-forest")
        resume.tap()
        XCTAssertTrue(app.webViews.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "这是纸间的隔离视觉验证书库")).firstMatch.waitForExistence(timeout: 15))
    }

    func testElevenThemesKeepTheActualHomeAndSearchReachable() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        for theme in ["forest", "classic", "kleinSage", "shuimo", "wuxia", "anime", "kawaii",
                      "porcelain", "inkstone", "hardcoverStudy", "pineSootMagazine"] {
            try launch(app, theme: theme)
            let current = currentBook(app, title: "剑来")
            let search = searchButton(app)
            XCTAssertTrue(search.isHittable, theme)
            if ["porcelain", "inkstone", "hardcoverStudy", "pineSootMagazine"].contains(theme) {
                XCTAssertGreaterThanOrEqual(current.frame.minY, app.frame.minY, theme)
                XCTAssertLessThanOrEqual(current.frame.maxY, search.frame.minY, theme)
                XCTAssertTrue(current.label.contains("继续阅读"), theme)
            } else {
                let maxCardHeight: CGFloat = (theme == "forest" || theme == "kleinSage") ? 266 : 380
                XCTAssertLessThanOrEqual(current.frame.height, maxCardHeight, theme)
            }
            XCTAssertTrue(tab(app, title: "主页", legacyID: "tabs.legacy.home").exists, theme)
            capture(app, name: "atelier-home-" + theme + "-light")
            app.terminate()
        }
    }

    func testFourAntigravityThemeCardsOpenRealProse() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        for theme in ["porcelain", "inkstone", "hardcoverStudy", "pineSootMagazine"] {
            try launch(app, theme: theme, presentation: "classic")
            let card = currentBook(app, title: "剑来")
            XCTAssertTrue(card.isHittable, theme)
            XCTAssertTrue(card.label.contains("继续阅读"), theme)
            capture(app, name: "antigravity-home-" + theme + "-light")
            card.tap()
            let prose = app.webViews.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "这是纸间的隔离视觉验证书库")).firstMatch
            XCTAssertTrue(prose.waitForExistence(timeout: 15), theme + " must open the real reader")
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
        dragOneBook(in: pager)
        currentBook(app, title: "月亮与六便士")
        XCTAssertEqual(filters.frame.midY, originalY, accuracy: 2)
        dragOneBook(in: pager)
        currentBook(app, title: "白昼之后")
        XCTAssertEqual(filters.frame.midY, originalY, accuracy: 2)
        capture(app, name: "atelier-home-pineMist-long-title")
    }

    func testFastFlingCanCrossMultipleBooksInClassicAndShowcase() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        for presentation in ["classic", "showcase"] {
            try launch(app, theme: "paper", presentation: presentation)
            currentBook(app, title: "剑来")
            let identifier = presentation == "classic" ? "bookshelf.readingPager" : "home.books.carousel"
            let pager = app.scrollViews[identifier].firstMatch
            XCTAssertTrue(pager.isHittable)
            // A drag with an end hold releases at rest; a swipe preserves fling velocity.
            pager.swipeLeft(velocity: .fast)
            let third = currentBook(app, title: "白昼之后")
            XCTAssertEqual(third.frame.midX, pager.frame.midX, accuracy: 24,
                "A fast fling must settle beyond the immediate next book, not merely expose an adjacent cover")
            capture(app, name: "home-multibook-fling-" + presentation)
            app.terminate()
        }
    }

    private func dragOneBook(in pager: XCUIElement) {
        // The product now preserves momentum, so a default fast swipe may skip the second book.
        pager.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).press(forDuration: 0.05,
            thenDragTo: pager.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)),
            withVelocity: .slow, thenHoldForDuration: 0.3)
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

    private func launch(_ app: XCUIApplication, theme: String, presentation: String? = "classic", hasLongShelf: Bool = false) throws {
        let cover = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "jianlai-cover", withExtension: "jpg"))
        app.launchEnvironment["SOURCEREAD_UI_COVER_JPEG"] = try Data(contentsOf: cover).base64EncodedString()
        app.launchArguments = ["--floating-desk-regression", "-settings.themeMode", "light",
            "-settings.visualTheme", theme, "-settings.readingDeskEnabled", "YES", "-settings.reducesMotion", "NO",
            "-settings.homeComposition", "auto",
            "-reader.mode", "scroll"]
        if let presentation {
            app.launchArguments += ["-settings.homeBookPresentation", presentation]
        } else {
            app.launchArguments.append("--desk-presentation-menu")
        }
        if hasLongShelf { app.launchArguments.append("--desk-shelf-scroll") }
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
