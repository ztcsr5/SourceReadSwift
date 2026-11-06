import XCTest

final class FloatingReadingDeskUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws { app.terminate() }

    func testHomeGlobalSearchFindsTheLocalBookAndOpensItsDetails() throws {
        try launch(theme: "forest")
        let search = element("bookshelf.globalSearch")
        XCTAssertTrue(search.isHittable)
        search.tap()
        let query = app.textFields["globalSearch.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText("剑来")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "globalSearch.result.book:")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("剑来"))
        capture("25-global-search-local-book")
        result.tap()
        let title = element("bookDetail.title")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "剑来")
    }

    func testDiscoverStartsWithoutAResultsHeadingAndUsesACompactMatchControl() throws {
        try launch(theme: "forest")
        rootTab("寻书", legacyID: "tabs.legacy.discover").tap()
        XCTAssertTrue(app.textFields["搜索书名或作者"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["搜索结果"].exists)
        let matchMode = element("discover.matchMode")
        XCTAssertTrue(matchMode.exists)
        XCTAssertLessThanOrEqual(matchMode.frame.width, 160)
        capture("26-discover-initial-state")
    }

    func testForestHomeAndAppearanceSwitchInTheRealApp() throws {
        try launch(theme: nil, fixture: "--forest-appearance-regression")
        let entry = assertCurrentBook("剑来")
        XCTAssertLessThan(entry.frame.height, 215, "The foreground book and glass must not occupy the old tall stage")
        let shelf = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bookshelf.grid.")).firstMatch
        XCTAssertTrue(shelf.isHittable, "A shelf cover remains visible on the first screen")
        XCTAssertFalse(shelf.label.contains("TXT"), "A grid jacket cannot expose an overlaid format badge")
        capture("20-forest-home")

        entry.press(forDuration: 0.8)
        let details = app.buttons["书籍详情"].firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertFalse(element("reader.webScrollSurface").exists)
        details.tap()
        XCTAssertTrue(element("bookDetail.title").waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))

        rootTab("设置", legacyID: "tabs.legacy.settings").tap()
        let appearance = app.buttons["外观"].firstMatch
        XCTAssertTrue(appearance.waitForExistence(timeout: 5)); appearance.tap()
        let forest = app.buttons["app.theme.forest"]
        let classic = app.buttons["app.theme.classic"]
        let themes = app.collectionViews.firstMatch
        if !forest.isHittable { themes.swipeUp() }
        XCTAssertTrue(forest.waitForExistence(timeout: 5))
        XCTAssertTrue(forest.isSelected)
        capture("21-forest-appearance")
        if !classic.isHittable { themes.swipeDown() }
        classic.tap()
        XCTAssertTrue(classic.isSelected)
        let home = rootTab("主页", legacyID: "tabs.legacy.home")
        home.tap()
        XCTAssertGreaterThan(assertCurrentBook("剑来").frame.height, 250)
        capture("22-classic-retained")

        rootTab("设置", legacyID: "tabs.legacy.settings").tap()
        if !forest.isHittable { themes.swipeUp() }
        XCTAssertTrue(forest.waitForExistence(timeout: 5)); forest.tap()
        home.tap()
        XCTAssertLessThan(assertCurrentBook("剑来").frame.height, 215)
        rootTab("寻书", legacyID: "tabs.legacy.discover").tap()
        XCTAssertTrue(app.textFields["搜索书名或作者"].waitForExistence(timeout: 5))
        capture("23-forest-search-segments")
    }

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
        XCTAssertFalse(element("reader.webScrollSurface").exists)
        let detail = app.buttons["书籍详情"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertFalse(element("reader.webScrollSurface").isHittable, "A management hold must not activate the reader")
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

    func testReadingDeskLongPressOffersTheSameBookActionsWithoutActivatingReader() throws {
        try launch(theme: "classic")
        assertCurrentBook("剑来").press(forDuration: 0.8)
        let detail = app.buttons["书籍详情"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["从书架删除"].firstMatch.exists)
        XCTAssertFalse(element("reader.webScrollSurface").exists)
        detail.tap()
        XCTAssertTrue(element("bookDetail.title").waitForExistence(timeout: 5))
        let home = rootTab("主页", legacyID: "tabs.legacy.home")
        XCTAssertTrue(home.isHittable, "The main bar stays visible on a normal detail")
        let lastChapter = app.buttons["山中来信"].firstMatch
        if !lastChapter.isHittable { element("bookDetail.scroll").swipeUp() }
        XCTAssertTrue(lastChapter.isHittable, "The last chapter can scroll fully above the bar")
        XCTAssertLessThanOrEqual(lastChapter.frame.maxY, home.frame.minY)
        capture("14-overflow-to-detail")

        let settings = rootTab("设置", legacyID: "tabs.legacy.settings")
        settings.tap()
        let appearance = app.buttons["外观"].firstMatch
        XCTAssertTrue(appearance.waitForExistence(timeout: 5)); appearance.tap()
        XCTAssertTrue(app.navigationBars["外观"].waitForExistence(timeout: 5))
        XCTAssertTrue(home.isHittable, "Normal settings subpages keep the main bar")
        home.tap()
        XCTAssertTrue(element("bookDetail.title").waitForExistence(timeout: 5), "Home retains its pushed detail")
        settings.tap()
        XCTAssertTrue(app.navigationBars["外观"].waitForExistence(timeout: 5), "Settings retains its pushed editor")
        capture("15-settings-tab-retained")
    }

    func testFirstReadingHasARealTitlePageAndLaterResumesDirectly() throws {
        try launch(theme: "classic", fixture: "--desk-first-reading")
        let cover = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "bookshelf.grid.", "月亮与六便士")).firstMatch
        if !cover.isHittable { app.swipeUp() }
        XCTAssertTrue(cover.isHittable); cover.tap()
        let read = app.buttons["bookDetail.read"]
        XCTAssertTrue(read.waitForExistence(timeout: 5)); read.tap()
        let start = app.buttons["bookTitlePage.read"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertFalse(element("reader.webScrollSurface").isHittable, "The title page is not a loading overlay")
        XCTAssertTrue(rootTab("主页", legacyID: "tabs.legacy.home").isHittable)
        capture("16-first-reading-title-page")
        app.navigationBars["书籍扉页"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(read.waitForExistence(timeout: 5)); read.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Looking at the title page cannot mark the book read")
        start.tap()
        assertReaderProse()
        returnFromReader()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        app.navigationBars["书籍扉页"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(read.waitForExistence(timeout: 5)); read.tap()
        assertReaderProse()
        XCTAssertFalse(start.isHittable, "An existing position skips the title page")
    }

    func testContinueRestoresTheSavedParagraphInTheRealWebView() throws {
        try launch(theme: "classic", fixture: "--desk-resume-paragraph")
        assertCurrentBook("剑来").tap()
        let surface = element("reader.webScrollSurface")
        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        let saved = app.webViews.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "【已保存的阅读段落】")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "Web startup state: \(surface.value ?? "unavailable")")
        XCTAssertTrue(surface.frame.intersects(saved.frame), "The saved paragraph must be in the actual viewport")
        XCTAssertFalse(rootTab("主页", legacyID: "tabs.legacy.home").isHittable)
        capture("17-restored-paragraph")
        surface.swipeUp()
        surface.swipeDown()
        XCTAssertTrue(surface.isHittable)
        returnFromReader()
        XCTAssertTrue(rootTab("主页", legacyID: "tabs.legacy.home").isHittable)
    }

    func testReadingDeskReaderAndReturnInTheRealApp() throws {
        try launch(theme: "classic")
        let pager = element("bookshelf.readingPager")
        let entry = assertCurrentBook("剑来")
        XCTAssertTrue(entry.isHittable); entry.tap()
        assertReaderProse()
        returnFromReader()
        XCTAssertTrue(pager.waitForExistence(timeout: 3))
        let home = rootTab("主页", legacyID: "tabs.legacy.home")
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

    func testContinuousChapterCrossingKeepsProseHeadingAndReopenedPositionTogether() throws {
        try launch(theme: "classic", fixture: "--desk-cross-chapter")
        let entry = assertCurrentBook("剑来")
        entry.tap()
        let surface = element("reader.webScrollSurface")
        let secondChapter = app.webViews.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "【连续章2·段1】")).firstMatch
        XCTAssertTrue(secondChapter.waitForExistence(timeout: 10))
        let back = element("reader.returnToShelf")
        if !back.isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)).tap() }
        XCTAssertTrue(back.isHittable)
        assertChapterAtViewportTop(2, surface: surface)
        var previousChapter = 2
        for chapter in [3, 2, 1, 2, 3] {
            let heading = element("reader.currentChapterHeading")
            let isForward = chapter > previousChapter
            for _ in 0..<10 {
                if heading.label == "连续阅读第\(chapter)章" { break }
                if isForward { surface.swipeUp() } else { surface.swipeDown() }
            }
            assertChapterAtViewportTop(chapter, surface: surface)
            capture("cross-chapter-\(chapter)")
            previousChapter = chapter
        }
        back.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        if !back.isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)).tap() }
        assertChapterAtViewportTop(3, surface: surface)
        capture("cross-chapter-reopened")
    }

    private func assertChapterAtViewportTop(_ chapter: Int, surface: XCUIElement) {
        let heading = element("reader.currentChapterHeading")
        let synchronized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard heading.label == "连续阅读第\(chapter)章" else { return false }
            let prose = self.app.webViews.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "【连续章\(chapter)·")).allElementsBoundByIndex
            // A prefetched offscreen paragraph is not evidence of crossing.
            return prose.contains { paragraph in
                let visible = paragraph.frame.intersection(surface.frame)
                return !visible.isNull && visible.height > 20 && visible.minY < surface.frame.midY
            }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [synchronized], timeout: 5), .completed,
                       "The real visible prose and native heading must agree on chapter \(chapter)")
        XCTAssertFalse(element("reader.openingRecovery").exists)
        XCTAssertFalse(rootTab("主页", legacyID: "tabs.legacy.home").isHittable)
    }

    func testReaderSystemReturnCanCancelWithoutLosingItsSavedParagraph() throws {
        try verifyNativeReturn(reducesMotion: false)
    }

    func testReaderSystemReturnCanCancelWithReducedMotion() throws {
        try verifyNativeReturn(reducesMotion: true)
    }

    private func verifyNativeReturn(reducesMotion: Bool) throws {
        try launch(theme: "classic", reducesMotion: reducesMotion, fixture: "--desk-resume-paragraph")
        let entry = assertCurrentBook("剑来")
        entry.tap()
        let surface = element("reader.webScrollSurface")
        let saved = app.webViews.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "【已保存的阅读段落】")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertFalse(element("reader.returnToShelf").isHittable, "Prose can return interactively without first opening its menu")
        let nativeEvidence = element("reader.nativeBookGestureEvidence")
        XCTAssertTrue(nativeEvidence.waitForExistence(timeout: 5))
        let motionBefore = Int((nativeEvidence.value as? String) ?? "") ?? (-1)
        XCTAssertGreaterThanOrEqual(motionBefore, 0)
        print("BOOK_NATIVE_CANCEL_BEFORE \(nativeEvidence.label)")
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.008, dy: 0.52))
        // Recording proved 40 px/s was ignored. Keep the recognized 250 px/s
        // control, but release below the previous 16%-width commit distance.
        edge.press(forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.10, dy: 0.52)),
            withVelocity: .slow, thenHoldForDuration: 0.8)
        XCTAssertTrue(surface.isHittable, "Cancel must keep the same real reader active")
        XCTAssertTrue(saved.exists && surface.frame.intersects(saved.frame))
        XCTAssertFalse(rootTab("主页", legacyID: "tabs.legacy.home").isHittable)
        let motionAfter = Int((nativeEvidence.value as? String) ?? "") ?? (-1)
        print("BOOK_NATIVE_CANCEL_AFTER \(nativeEvidence.label)")
        XCTAssertGreaterThan(motionAfter, motionBefore, "A real native gesture must move; an ignored drag is not cancellation")
        print("BOOK_NATIVE_CANCEL_VERIFIED motion_before=\(motionBefore) motion_after=\(motionAfter)")
        capture("18-reader-native-return-cancelled")
        edge.press(forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.52)),
            withVelocity: .default, thenHoldForDuration: 0.4)
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == YES"), object: entry)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
        XCTAssertTrue(rootTab("主页", legacyID: "tabs.legacy.home").isHittable)
        capture("19-reader-native-return-completed")
        entry.tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertTrue(surface.frame.intersects(saved.frame), "Reopening after cancel/finish must preserve the saved paragraph")
        returnFromReader()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
    }

    func testOtherThemesAndIndependentOldStyleSwitch() throws {
        try launch(theme: "botanical")
        capture("07-botanical-home")
        assertCurrentBook("剑来").press(forDuration: 0.8)
        element("bookshelf.floatingDeskToggle").tap()
        XCTAssertFalse(element("bookshelf.readingPager").exists)
        capture("08-previous-compact-desk")
        assertCurrentBook("剑来").press(forDuration: 0.8)
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

    func testCollapsedShelfFiltersPreserveQueryAndThemeLayoutsHaveRealEntries() throws {
        try launch(theme: "forest")
        let search = app.textFields["在书架中搜索书名或作者..."]
        XCTAssertFalse(search.exists)
        let filters = app.buttons["bookshelf.filters"]
        XCTAssertTrue(filters.isHittable)
        filters.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("剑来")
        filters.tap()
        XCTAssertFalse(search.exists)
        XCTAssertEqual(filters.value as? String, "已启用筛选")
        filters.tap()
        XCTAssertEqual(search.value as? String, "剑来")
        capture("23-collapsed-shelf-filter")
        app.terminate()
        for theme in ["editorial", "blueprint", "folio"] {
            try launch(theme: theme)
            let entry = assertCurrentBook("剑来")
            XCTAssertTrue(entry.isHittable)
            XCTAssertTrue(app.buttons["bookshelf.globalSearch"].isHittable)
            capture("24-theme-layout-" + theme)
            entry.press(forDuration: 0.8)
            XCTAssertTrue(app.buttons["书籍详情"].firstMatch.waitForExistence(timeout: 3))
            XCTAssertFalse(element("reader.webScrollSurface").exists)
            app.terminate()
        }
    }

    func testSimulatorPagingPerformanceEvidenceNotADeviceFPSClaim() throws {
        try launch(theme: "classic")
        measurePaging("bookshelf.readingPager")
    }

    func testPreviousStyleSimulatorPagingPerformanceBaseline() throws {
        try launch(theme: "classic")
        assertCurrentBook("剑来").press(forDuration: 0.8)
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

    private func launch(theme: String?, mode: String = "light", reducesMotion: Bool = false, fixture: String? = nil) throws {
        let reference = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "jianlai-cover", withExtension: "jpg"))
        let cover = try Data(contentsOf: reference)
        XCTAssertLessThanOrEqual(cover.count, 128_000)
        app.launchEnvironment["SOURCEREAD_UI_COVER_JPEG"] = cover.base64EncodedString()
        app.launchArguments = ["--floating-desk-regression",
            "-settings.themeMode", mode, "-settings.readingDeskEnabled", "YES",
            "-settings.reducesMotion", reducesMotion ? "YES" : "NO", "-reader.mode", "scroll",
            "-reader.textSelectionEnabled", "NO"]
        if let fixture { app.launchArguments.append(fixture) }
        if let theme { app.launchArguments += ["-settings.visualTheme", theme] }
        app.launch()
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bookshelf.continue.")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
    }

    private func rootTab(_ label: String, legacyID: String) -> XCUIElement {
        let legacy = app.buttons[legacyID]
        return legacy.exists ? legacy : app.tabBars.firstMatch.buttons[label]
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
        let isProseReady = prose.waitForExistence(timeout: 12)
        if !isProseReady { capture("reader-prose-startup-failure") }
        XCTAssertTrue(isProseReady, "Check actual chapter prose, not only the existence of a WebView")
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
