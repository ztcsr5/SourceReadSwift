import XCTest

final class FloatingReadingDeskUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws { app.terminate() }

    func testWhiteVioletPagingDetailsReaderAndReturnInTheRealApp() {
        launch(theme: "classic")
        capture("01-pearl-violet-home")
        XCTAssertTrue(app.staticTexts["最近阅读 · 1 / 3"].waitForExistence(timeout: 3))
        let pager = element("bookshelf.readingPager")
        XCTAssertTrue(pager.isHittable)
        let start = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.76, dy: 0.5))
        let shortDrag = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: shortDrag, withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(app.staticTexts["最近阅读 · 1 / 3"].waitForExistence(timeout: 3), "A cancelled short drag must keep the same book")
        capture("01b-short-drag-cancelled")
        pager.swipeLeft()
        XCTAssertTrue(app.staticTexts["最近阅读 · 2 / 3"].waitForExistence(timeout: 3))
        capture("02-plain-cover")
        pager.swipeLeft()
        XCTAssertTrue(app.staticTexts["最近阅读 · 3 / 3"].waitForExistence(timeout: 3))
        capture("03-missing-cover-long-title")
        pager.swipeRight(); pager.swipeRight()
        XCTAssertTrue(app.staticTexts["最近阅读 · 1 / 3"].waitForExistence(timeout: 3))
        app.buttons["正在阅读书籍的更多操作"].firstMatch.tap()
        app.buttons["书籍详情"].firstMatch.tap()
        XCTAssertFalse(pager.isHittable)
        capture("04-real-book-details")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(pager.waitForExistence(timeout: 3))
        capture("05-return-to-desk")
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bookshelf.continue.")).firstMatch
        XCTAssertTrue(entry.isHittable); entry.tap()
        let returnButton = element("reader.returnToShelf")
        if !returnButton.isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)).tap() }
        XCTAssertTrue(returnButton.waitForExistence(timeout: 5)); returnButton.tap()
        XCTAssertTrue(pager.waitForExistence(timeout: 3))
        let tabs = app.tabBars.firstMatch
        let home = tabs.exists ? tabs.buttons["主页"] : app.buttons["主页"]
        XCTAssertTrue(home.isHittable, "Returning to the real shelf must restore navigation with it")
        capture("06-reader-return-root")
    }

    func testOtherThemesAndIndependentOldStyleSwitch() {
        launch(theme: "botanical")
        capture("07-botanical-home")
        app.buttons["正在阅读书籍的更多操作"].firstMatch.tap()
        element("bookshelf.floatingDeskToggle").tap()
        XCTAssertFalse(element("bookshelf.readingPager").exists)
        capture("08-previous-compact-desk")
        app.buttons["正在阅读书籍的更多操作"].firstMatch.tap()
        element("bookshelf.floatingDeskToggle").tap()
        XCTAssertTrue(element("bookshelf.readingPager").waitForExistence(timeout: 3))
        capture("09-restored-floating-desk")
        app.terminate()
        launch(theme: "classic", mode: "dark")
        capture("10-dark-home")
        app.terminate()
        launch(theme: "classic", reducesMotion: true)
        XCTAssertFalse(element("bookshelf.readingPager").exists)
        app.buttons["下一本最近阅读"].tap()
        XCTAssertTrue(app.staticTexts["最近阅读 · 2 / 3"].waitForExistence(timeout: 3))
        capture("11-reduced-motion-stepper")
    }

    func testSimulatorPagingPerformanceEvidenceNotADeviceFPSClaim() {
        launch(theme: "classic")
        let options = XCTMeasureOptions(); options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app),
            XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) {
            let pager = element("bookshelf.readingPager")
            pager.swipeLeft(); pager.swipeLeft(); pager.swipeRight(); pager.swipeRight()
        }
        XCTAssertTrue(app.staticTexts["最近阅读 · 1 / 3"].exists)
    }

    private func launch(theme: String, mode: String = "light", reducesMotion: Bool = false) {
        app.launchArguments = ["--floating-desk-regression", "-settings.visualTheme", theme,
            "-settings.themeMode", mode, "-settings.readingDeskEnabled", "YES",
            "-settings.reducesMotion", reducesMotion ? "YES" : "NO", "-reader.mode", "scroll"]
        app.launch()
        XCTAssertTrue(app.buttons["正在阅读书籍的更多操作"].firstMatch.waitForExistence(timeout: 10))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "floating-desk-" + name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
