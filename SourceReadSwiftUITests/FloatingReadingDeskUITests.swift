import XCTest

final class FloatingReadingDeskUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws { app.terminate() }

    func testWhiteVioletPagingAndCancelledDragInTheRealApp() throws {
        try launch(theme: "classic")
        capture("01-pearl-violet-home")
        assertCurrentBook("剑来")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "最近阅读 · ")).firstMatch.exists)
        let pager = element("bookshelf.readingPager")
        XCTAssertTrue(pager.isHittable)
        let start = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.76, dy: 0.5))
        let shortDrag = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: shortDrag, withVelocity: .slow, thenHoldForDuration: 0.3)
        assertCurrentBook("剑来")
        capture("01b-short-drag-cancelled")
        pager.swipeLeft()
        assertCurrentBook("月亮与六便士")
        capture("02-plain-cover")
        pager.swipeLeft()
        assertCurrentBook("白昼之后")
        capture("03-missing-cover-long-title")
        pager.swipeRight(); pager.swipeRight()
        assertCurrentBook("剑来")
    }

    func testReadingDeskDetailsAndReturnInTheRealApp() throws {
        try launch(theme: "classic")
        let pager = element("bookshelf.readingPager")
        let entry = assertCurrentBook("剑来")
        entry.coordinate(withNormalizedOffset: CGVector(dx: 0.47, dy: 0.34)).press(forDuration: 0.8)
        let detail = app.buttons["书籍详情"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertFalse(element("reader.webScrollSurface").exists, "Holding the book must not activate the reader")
        XCTAssertTrue(app.buttons["从书架删除"].firstMatch.exists)
        detail.tap()
        XCTAssertTrue(element("bookDetail.title").waitForExistence(timeout: 5))
        XCTAssertFalse(pager.isHittable)
        capture("04-real-book-details")
        let read = app.buttons["bookDetail.read"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        read.tap()
        assertReaderProse()
        capture("04a-reader-first-chapter")
        returnFromReader()
        XCTAssertTrue(read.waitForExistence(timeout: 5), "Reader must return to the same detail, not the shelf")
        capture("04b-reader-returned-to-detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(pager.waitForExistence(timeout: 3))
        capture("05-return-to-desk")
        assertCurrentBook("剑来")
    }

    func testReadingDeskOverflowOffersTheSameBookActionsWithoutActivatingReader() throws {
        try launch(theme: "classic")
        app.buttons["正在阅读书籍的更多操作"].firstMatch.tap()
        let detail = app.buttons["书籍详情"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["从书架删除"].firstMatch.exists)
        XCTAssertFalse(element("reader.webScrollSurface").exists)
        detail.tap()
        XCTAssertTrue(element("bookDetail.title").waitForExistence(timeout: 5))
        let tabs = app.tabBars.firstMatch
        let home = tabs.exists ? tabs.buttons["主页"] : app.buttons["tabs.legacy.home"]
        // The iOS 18 back button is also labelled “主页”; query the actual bottom control.
        capture("14-overflow-to-detail")
        XCTAssertFalse(home.isHittable, "Root navigation must not overlap detail chapters")
    }

    func testReadingDeskReaderAndReturnInTheRealApp() throws {
        try launch(theme: "classic")
        let pager = element("bookshelf.readingPager")
        let entry = assertCurrentBook("剑来")
        XCTAssertTrue(entry.isHittable); entry.tap()
        assertReaderProse()
        returnFromReader()
        XCTAssertTrue(pager.waitForExistence(timeout: 3))
        let tabs = app.tabBars.firstMatch
        let home = tabs.exists ? tabs.buttons["主页"] : app.buttons["tabs.legacy.home"]
        XCTAssertTrue(home.isHittable, "Returning to the real shelf must restore navigation with it")
        capture("06-reader-return-root")
    }

    func testShelfCoverReturnsToItsSlotAfterCancelledAndCompletedEdgeGestures() throws {
        try launch(theme: "classic")
        let cover = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "bookshelf.grid.", "月亮与六便士")).firstMatch
        if !cover.isHittable { app.swipeUp() }
        XCTAssertTrue(cover.isHittable)
        let origin = cover.frame
        cover.tap()
        let detail = element("bookDetail.title")
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertEqual(detail.label, "月亮与六便士")
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.008, dy: 0.52))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.52)),
            withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(detail.isHittable, "A cancelled native pop must leave the same detail active")
        capture("12-shelf-pop-cancelled")
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.52)),
            withVelocity: .default, thenHoldForDuration: 0.15)
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertTrue(cover.isHittable)
        XCTAssertEqual(cover.frame.midX, origin.midX, accuracy: 3)
        XCTAssertEqual(cover.frame.midY, origin.midY, accuracy: 8)
        capture("13-shelf-pop-original-slot")
        // Reopen immediately after the completed pop; a single back must reach home.
        cover.tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        // iOS 18 may return from tap() while the native zoom is still hiding
        // its source. Wait for the end condition, never a fixed sleep.
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == YES"), object: cover)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
        XCTAssertTrue(cover.isHittable)
        XCTAssertFalse(detail.isHittable)
        XCTAssertEqual(cover.frame.midX, origin.midX, accuracy: 3)
        XCTAssertEqual(cover.frame.midY, origin.midY, accuracy: 8)
    }

    func testOtherThemesAndIndependentOldStyleSwitch() throws {
        try launch(theme: "botanical")
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
        try launch(theme: "classic", mode: "dark")
        capture("10-dark-home")
        app.terminate()
        try launch(theme: "classic", reducesMotion: true)
        XCTAssertFalse(element("bookshelf.readingPager").exists)
        app.buttons["下一本最近阅读"].tap()
        assertCurrentBook("月亮与六便士")
        capture("11-reduced-motion-stepper")
    }

    func testSimulatorPagingPerformanceEvidenceNotADeviceFPSClaim() throws {
        try launch(theme: "classic")
        measurePaging("bookshelf.readingPager")
    }

    func testPreviousStyleSimulatorPagingPerformanceBaseline() throws {
        try launch(theme: "classic")
        app.buttons["正在阅读书籍的更多操作"].firstMatch.tap()
        element("bookshelf.floatingDeskToggle").tap()
        measurePaging("bookshelf.legacyReadingPager")
    }

    private func measurePaging(_ identifier: String) {
        let options = XCTMeasureOptions(); options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app),
            XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) {
            let pager = element(identifier)
            pager.swipeLeft(); pager.swipeLeft(); pager.swipeRight(); pager.swipeRight()
        }
        assertCurrentBook("剑来")
    }

    private func launch(theme: String, mode: String = "light", reducesMotion: Bool = false) throws {
        let reference = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "jianlai-cover", withExtension: "jpg"))
        let cover = try Data(contentsOf: reference)
        XCTAssertLessThanOrEqual(cover.count, 128_000)
        app.launchEnvironment["SOURCEREAD_UI_COVER_JPEG"] = cover.base64EncodedString()
        app.launchArguments = ["--floating-desk-regression", "-settings.visualTheme", theme,
            "-settings.themeMode", mode, "-settings.readingDeskEnabled", "YES",
            "-settings.reducesMotion", reducesMotion ? "YES" : "NO", "-reader.mode", "scroll"]
        app.launch()
        XCTAssertTrue(app.buttons["正在阅读书籍的更多操作"].firstMatch.waitForExistence(timeout: 10))
    }

    private func element(_ identifier: String) -> XCUIElement {
        if identifier == "bookshelf.readingPager" { return app.scrollViews[identifier].firstMatch }
        return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func returnFromReader() {
        let returnButton = element("reader.returnToShelf")
        XCTAssertTrue(element("reader.webScrollSurface").waitForExistence(timeout: 8))
        if !returnButton.isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)).tap() }
        XCTAssertTrue(returnButton.waitForExistence(timeout: 5))
        returnButton.tap()
    }

    private func assertReaderProse() {
        let prose = app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "这是纸间的隔离视觉验证书库")).firstMatch
        XCTAssertTrue(prose.waitForExistence(timeout: 12), "Check actual chapter prose, not only the existence of a WebView")
    }

    @discardableResult private func assertCurrentBook(_ title: String) -> XCUIElement {
        let book = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "bookshelf.continue.", title)).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 5), "The selected real book must exist")
        XCTAssertTrue(book.isHittable, "The selected book must be onscreen, not an offscreen page")
        return book
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "floating-desk-" + name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
