import XCTest

final class FloatingReadingDeskUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws { app.terminate() }

    func testHomeGlobalSearchOnlyFindsAppFunctions() throws {
        try launch(theme: "forest")
        let search = globalSearchButton()
        XCTAssertTrue(search.isHittable)
        search.tap()
        let query = globalSearchField()
        XCTAssertTrue(query.exists)
        query.tap()
        query.typeText("剑来")
        let bookResult = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "globalSearch.result.book:")).firstMatch
        XCTAssertFalse(bookResult.waitForExistence(timeout: 2),
                       "Global search must not index books or book details")
        XCTAssertTrue(app.staticTexts["没有匹配的功能入口。"].waitForExistence(timeout: 5))
        capture("25-global-search-functions-only")
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

    func testFirstReadingOpensProseAndLaterResumesDirectly() throws {
        try launch(theme: "classic", fixture: "--desk-first-reading")
        let cover = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "bookshelf.grid.", "月亮与六便士")).firstMatch
        if !cover.isHittable { app.swipeUp() }
        XCTAssertTrue(cover.isHittable); cover.tap()
        let read = app.buttons["bookDetail.read"]
        XCTAssertTrue(read.waitForExistence(timeout: 5)); read.tap()
        assertReaderProse()
        XCTAssertFalse(app.buttons["bookTitlePage.read"].exists, "First reading must enter prose without an extra title-page route")
        XCTAssertFalse(rootTab("主页", legacyID: "tabs.legacy.home").isHittable)
        capture("16-first-reading-prose")
        returnFromReader()
        XCTAssertTrue(read.waitForExistence(timeout: 5), "The first reader must return directly to its owning detail")
        XCTAssertEqual(element("bookDetail.title").label, "月亮与六便士")
        XCTAssertTrue(rootTab("主页", legacyID: "tabs.legacy.home").isHittable)
        read.tap()
        assertReaderProse()
        XCTAssertFalse(app.buttons["bookTitlePage.read"].exists)
        returnFromReader()
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(cover.waitForExistence(timeout: 3))
        XCTAssertTrue(cover.isHittable)
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

    func testFirstDetailEdgeReturnRestoresInteractiveHomeAndOnlyOneTabBar() throws {
        try launch(theme: "forest")
        let cover = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "bookshelf.grid.", "月亮与六便士")).firstMatch
        if !cover.isHittable { app.swipeUp() }
        XCTAssertTrue(cover.isHittable)
        cover.tap()
        XCTAssertTrue(element("bookDetail.title").waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.008, dy: 0.52))
            .press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.52)),
                withVelocity: .default, thenHoldForDuration: 0.15)
        let readiness = element("bookshelf.returnReadiness")
        XCTAssertFalse(readiness.exists, "返回就绪探针已移除，不应再存在于界面上")
        XCTAssertTrue(cover.isHittable, "首次 pop 后书架必须可点")
        XCTAssertTrue(cover.isHittable)
        XCTAssertFalse(element("bookDetail.title").isHittable)
        XCTAssertTrue(rootTab("主页", legacyID: "tabs.legacy.home").isHittable)
        XCTAssertLessThanOrEqual(app.tabBars.allElementsBoundByIndex.filter(\.isHittable).count, 1,
            "At most one system tab bar may be interactive; the custom bar and the native bar must not stack")
        let search = globalSearchButton()
        XCTAssertTrue(search.isHittable)
        search.tap()
        XCTAssertTrue(globalSearchField(timeout: 1).exists)
        capture("detail-first-pop-responsive-home")
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
                if heading.exists && heading.label == "连续阅读第\(chapter)章" { break }
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
            // XCUI resolves each frame via the remote accessibility service.
            // Use one coherent viewport for every paragraph in this sample.
            let viewport = surface.frame
            guard !viewport.isEmpty else { return false }
            let prose = self.app.webViews.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "【连续章\(chapter)·")).allElementsBoundByIndex
            // A prefetched offscreen paragraph is not evidence of crossing.
            return prose.contains { paragraph in
                let visible = paragraph.frame.intersection(viewport)
                return !visible.isNull && visible.height > 20 && visible.minY < viewport.midY
            }
        }, object: nil)
        let outcome = XCTWaiter.wait(for: [synchronized], timeout: 5)
        if outcome != .completed { capture("cross-chapter-failure-\(chapter)") }
        XCTAssertEqual(outcome, .completed,
                       "The real visible prose and native heading must agree on chapter \(chapter)")
        XCTAssertFalse(element("reader.openingRecovery").exists)
        XCTAssertFalse(rootTab("主页", legacyID: "tabs.legacy.home").isHittable)
    }

    func testReaderLongEdgeReturnCompletesWithReducedMotion() throws {
        try launch(theme: "classic", reducesMotion: true, fixture: "--desk-resume-paragraph")
        let entry = assertCurrentBook("剑来")
        entry.tap()
        let saved = app.webViews.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "【已保存的阅读段落】")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertFalse(element("reader.returnToShelf").isHittable)

        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.008, dy: 0.52))
        edge.press(forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.52)),
            withVelocity: .default, thenHoldForDuration: 0.4)
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == YES"), object: entry)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
        XCTAssertTrue(rootTab("主页", legacyID: "tabs.legacy.home").isHittable)
        capture("27-reader-long-edge-return-control")
        entry.tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertTrue(element("reader.webScrollSurface").frame.intersects(saved.frame))
    }

    func testReaderSystemReturnCanCancelWithoutLosingItsSavedParagraph() throws {
        try verifyNativeReturn(reducesMotion: false)
    }

    func testReaderSystemReturnCanCancelWithReducedMotion() throws {
        try verifyNativeReturn(reducesMotion: true)
    }

    func testNativeReturnCancellationWithLongerSubthresholdDrag() throws {
        try verifyNativeReturn(reducesMotion: false, cancelFraction: 0.20)
    }

    private func verifyNativeReturn(reducesMotion: Bool, cancelFraction: CGFloat = 0.13) throws {
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
        let fallbackEvidence = element("reader.fallbackGestureEvidence")
        XCTAssertTrue(fallbackEvidence.waitForExistence(timeout: 5))
        let fallbackBefore = Int((fallbackEvidence.value as? String) ?? "") ?? (-1)
        XCTAssertGreaterThanOrEqual(fallbackBefore, 0)
        let motionBefore = Int((nativeEvidence.value as? String) ?? "") ?? (-1)
        XCTAssertGreaterThanOrEqual(motionBefore, 0)
        print("BOOK_NATIVE_CANCEL_BEFORE \(nativeEvidence.label)")
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.008, dy: 0.52))
        // Let the document settle before synthesizing the edge drag; an
        // in-flight mount can swallow the first touch sequence.
        Thread.sleep(forTimeInterval: 0.4)
        // Recording proved 40 px/s was ignored. Keep the recognized 250 px/s
        // control, but release below the previous 16%-width commit distance.
        // A 0.05 s press was too short for the system edge recognizer under
        // XCUITest; 0.2 s still begins the pan without becoming a long press.
        edge.press(forDuration: 0.2,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: cancelFraction, dy: 0.52)),
            withVelocity: .slow, thenHoldForDuration: 0.8)
        XCTAssertTrue(surface.isHittable, "Cancel must keep the same real reader active")
        XCTAssertTrue(saved.exists && surface.frame.intersects(saved.frame))
        XCTAssertFalse(rootTab("主页", legacyID: "tabs.legacy.home").isHittable)
        var motionAfter = Int((nativeEvidence.value as? String) ?? "") ?? (-1)
        if !reducesMotion, motionAfter == motionBefore {
            // XCUITest can drop the first synthetic edge drag before WebKit has
            // attached its scroll pan. Retry the same sub-threshold gesture;
            // a truly ignored edge return still leaves the counter unchanged and
            // fails the assertion below.
            Thread.sleep(forTimeInterval: 0.3)
            edge.press(forDuration: 0.2,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: cancelFraction, dy: 0.52)),
                withVelocity: .slow, thenHoldForDuration: 0.8)
            XCTAssertTrue(surface.isHittable, "Cancel must keep the same real reader active")
            motionAfter = Int((nativeEvidence.value as? String) ?? "") ?? (-1)
        }
        print("BOOK_NATIVE_CANCEL_AFTER \(nativeEvidence.label)")
        if reducesMotion {
            let fallbackAfter = Int((fallbackEvidence.value as? String) ?? "") ?? (-1)
            XCTAssertGreaterThanOrEqual(fallbackAfter, 0)
            XCTAssertGreaterThan(motionAfter + fallbackAfter, motionBefore + fallbackBefore,
                                 "Reduced motion still requires a real recognized native or fallback drag; stable ignored input is not cancellation")
            print("BOOK_REDUCED_CANCEL_VERIFIED native_before=\(motionBefore) native_after=\(motionAfter) fallback_before=\(fallbackBefore) fallback_after=\(fallbackAfter)")
        } else {
            let fallbackAfter = Int((fallbackEvidence.value as? String) ?? "") ?? (-1)
            XCTAssertGreaterThanOrEqual(fallbackAfter, 0)
            XCTAssertTrue(motionAfter > motionBefore || fallbackAfter > fallbackBefore,
                          "A real native or fallback gesture must move; an ignored drag is not cancellation")
            print("BOOK_NATIVE_CANCEL_VERIFIED motion_before=\(motionBefore) motion_after=\(motionAfter) fallback_before=\(fallbackBefore) fallback_after=\(fallbackAfter)")
        }
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
        let pagerInDark = element("bookshelf.readingPager").exists
        app.terminate()
        // 「减少 App 动态效果」已从 App 删除，`-settings.reducesMotion` 现在是
        // 空操作。旧断言期望打开它之后翻页书台消失，那正是被删掉的行为。
        // 新契约：这个启动参数不得再改变任何阅读台形态。
        try launch(theme: "classic", reducesMotion: true)
        XCTAssertEqual(element("bookshelf.readingPager").exists, pagerInDark,
                       "动效开关已移除，-settings.reducesMotion 不得再改变阅读台形态")
        app.buttons["下一本最近阅读"].tap()
        assertCurrentBook("月亮与六便士")
        capture("11-motion-toggle-removed")
    }

    func testCollapsedShelfFiltersPreserveQueryAndThemeLayoutsHaveRealEntries() throws {
        // The query arrives through the launch-argument domain rather than the
        // keyboard: the property under test is that collapsing the filter bar
        // keeps the query, not that the simulator can synthesize CJK input.
        try launch(theme: "forest", shelfQuery: "剑来")
        let search = app.textFields["bookshelf.filterQuery"]
        let filters = app.buttons["bookshelf.filters"]
        XCTAssertTrue(filters.isHittable)
        XCTAssertEqual(filters.value as? String, "已启用筛选")
        XCTAssertFalse(search.exists, "A collapsed filter bar shows no query field")

        filters.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertEqual(search.value as? String, "剑来")
        capture("23-collapsed-shelf-filter-open")

        filters.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == NO"), object: search)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 3), .completed)
        XCTAssertEqual(filters.value as? String, "已启用筛选")
        capture("23-collapsed-shelf-filter")

        filters.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertEqual(search.value as? String, "剑来", "Reopening the filter bar must restore the typed query")
        app.terminate()
        for theme in ["editorial", "blueprint", "folio"] {
            try launch(theme: theme)
            let entry = assertCurrentBook("剑来")
            XCTAssertTrue(entry.isHittable)
            XCTAssertTrue(globalSearchButton().isHittable)
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

    private func launch(theme: String?, mode: String = "light", reducesMotion: Bool = false, fixture: String? = nil, shelfQuery: String? = nil) throws {
        let reference = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "jianlai-cover", withExtension: "jpg"))
        let cover = try Data(contentsOf: reference)
        XCTAssertLessThanOrEqual(cover.count, 128_000)
        app.launchEnvironment["SOURCEREAD_UI_COVER_JPEG"] = cover.base64EncodedString()
        app.launchArguments = ["--floating-desk-regression",
            "-settings.themeMode", mode, "-settings.readingDeskEnabled", "YES",
            "-settings.reducesMotion", reducesMotion ? "YES" : "NO", "-reader.mode", "scroll",
            "-reader.textSelectionEnabled", "NO"]
        if let fixture { app.launchArguments.append(fixture) }
        if let shelfQuery { app.launchArguments += ["-bookshelf.filterQuerySeed", shelfQuery] }
        if let theme { app.launchArguments += ["-settings.visualTheme", theme] }
        app.launch()
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bookshelf.continue.")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
    }

    private func globalSearchButton() -> XCUIElement {
        let legacy = app.buttons["bookshelf.globalSearch"]
        if legacy.exists { return legacy }
        let native = app.tabBars.buttons["搜索"]
        return native.exists ? native : app.buttons["搜索"]
    }

    /// 搜索页改用系统 `.searchable` 后，输入框的 element type 变成 searchField。
    /// 旧 identifier 只在 sheet 形态保留，按存在性二选一。
    private func globalSearchField(timeout: TimeInterval = 5) -> XCUIElement {
        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: timeout) { return searchField }
        return app.textFields["globalSearch.query"]
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
        let isProseReady = prose.waitForExistence(timeout: 45)
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
