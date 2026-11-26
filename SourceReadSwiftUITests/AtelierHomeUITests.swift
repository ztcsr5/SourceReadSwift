import XCTest
import UIKit

final class AtelierHomeUITests: XCTestCase {
    func testHardcoverDetailBackRestoresOnlyTheEditionDock() throws {
        try verifyEditionReturn(theme: "hardcoverStudy", shelfHeading: "我的藏书架", detailHeading: "书籍档案")
    }

    func testMagazineDetailEdgeReturnRestoresOnlyTheEditionDock() throws {
        try verifyEditionReturn(theme: "pineSootMagazine", shelfHeading: "近期书架", detailHeading: "藏书档案")
    }

    private func verifyEditionReturn(theme: String, shelfHeading: String, detailHeading: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        try launch(app, theme: theme, presentation: "showcase", fixture: "--desk-single-book")
        let card = currentBook(app, title: "剑来")
        XCTAssertLessThanOrEqual(card.frame.maxY, searchButton(app).frame.minY, "The cover host must not expand beyond the first screen")
        XCTAssertTrue(app.staticTexts[shelfHeading].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.scrollViews["home.books.carousel"].exists)
        assertSingleEditionDock(app)
        capture(app, name: "reference-edition-" + theme + "-home")
        try assertEditionCoverIsDrawn(on: card, magazine: theme == "pineSootMagazine")

        card.press(forDuration: 0.9)
        let details = app.buttons["书籍详情"].firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 5)); details.tap()
        let bar = app.navigationBars[detailHeading]
        XCTAssertTrue(bar.waitForExistence(timeout: 8))
        let read = app.buttons["bookDetail.read"].firstMatch
        XCTAssertTrue(read.waitForExistence(timeout: 8) && read.isHittable)
        XCTAssertTrue(app.staticTexts[theme == "pineSootMagazine" ? "当前书源" : "外观微缩画廊"].firstMatch.exists)
        if theme == "pineSootMagazine" { XCTAssertTrue(app.staticTexts["目录索引"].firstMatch.exists) }
        XCTAssertFalse(app.buttons["tabs.legacy.home"].exists)
        XCTAssertFalse(app.tabBars.buttons["主页"].isHittable)
        capture(app, name: "reference-edition-" + theme + "-detail")

        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.008, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.13, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(read.isHittable)
        XCTAssertFalse(app.buttons["tabs.legacy.home"].exists)
        if theme == "pineSootMagazine" {
            edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        } else {
            bar.buttons.element(boundBy: 0).tap()
        }
        assertSingleEditionDock(app)
        capture(app, name: "reference-edition-" + theme + "-returned")
        app.buttons["tabs.legacy.discover"].tap()
        XCTAssertTrue(app.navigationBars["寻书"].waitForExistence(timeout: 8))
        tab(app, title: "主页", legacyID: "tabs.legacy.home").tap()
        assertSingleEditionDock(app)
        if theme == "hardcoverStudy" {
            card.tap()
            let prose = app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "这是纸间的隔离视觉验证书库")).firstMatch
            XCTAssertTrue(prose.waitForExistence(timeout: 15), "A short tap must still open the actual chapter")
        }
    }

    private func assertSingleEditionDock(_ app: XCUIApplication) {
        let home = app.buttons["tabs.legacy.home"]
        XCTAssertTrue(home.waitForExistence(timeout: 8) && home.isHittable)
        XCTAssertTrue(app.buttons["bookshelf.globalSearch"].isHittable)
        let evidence = app.otherElements["bookshelf.chromeEvidence"]
        XCTAssertTrue((evidence.value as? String)?.contains("nativeDock=false;") == true,
                      "A second, even non-hittable, UIKit tab bar must not be drawn: \(String(describing: evidence.value))")
    }

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
            try launch(app, theme: "paper", presentation: presentation, fixture: "--desk-shelf-scroll")
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

    private func launch(_ app: XCUIApplication, theme: String, presentation: String? = "classic", fixture: String? = nil) throws {
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
        if let fixture { app.launchArguments.append(fixture) }
        app.launch()
    }

    @discardableResult private func currentBook(_ app: XCUIApplication, title: String) -> XCUIElement {
        let book = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "bookshelf.continue.", title)).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 8))
        XCTAssertTrue(book.isHittable)
        return book
    }

    private func assertEditionCoverIsDrawn(on card: XCUIElement, magazine: Bool) throws {
        let image = try XCTUnwrap(card.screenshot().image.cgImage)
        let width = CGFloat(image.width), height = CGFloat(image.height)
        // Sample the illustrated middle of the seeded jacket, away from text, borders and buttons.
        let region = CGRect(x: width * (magazine ? 0.77 : 0.42), y: height * 0.24,
                            width: width * 0.16, height: height * 0.23)
        let art = try XCTUnwrap(image.cropping(to: region.integral))
        var ink = [UInt8](repeating: 0, count: 16 * 16)
        try ink.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 16, height: 16, bitsPerComponent: 8,
                bytesPerRow: 16, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
            context.interpolationQuality = .high
            context.draw(art, in: CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        XCTAssertGreaterThan(ink.filter { $0 < 128 }.count, ink.count / 16, "The main cover must show the seeded artwork, not an empty frame")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
