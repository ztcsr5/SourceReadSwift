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
        revealRootTab("寻书", legacyID: "tabs.legacy.discover").tap()
        XCTAssertTrue(app.textFields["搜索书名或作者"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["搜索结果"].exists)
        let matchMode = element("discover.matchMode")
        XCTAssertTrue(matchMode.exists)
        XCTAssertLessThanOrEqual(matchMode.frame.width, 160)
        capture("26-discover-initial-state")
    }

    func testAIAndWebSourceWritingAreReachableFromRootSettings() throws {
        try launch(theme: "forest", extraArguments: ["-settings.ai.assistant_mode", "api"])
        revealRootTab("设置", legacyID: "tabs.legacy.settings").tap()
        for (identifier, title) in [("settings.aiAssistant", "AI 助手"),
                                   ("settings.webSourceWriting", "Web 写源与传输")] {
            let link = element(identifier)
            if !link.isHittable { app.swipeUp() }
            XCTAssertTrue(link.waitForExistence(timeout: 5) && link.isHittable)
            link.tap()
            let destination = app.navigationBars[title]
            XCTAssertTrue(destination.waitForExistence(timeout: 5), "Open \(title) directly from Settings")
            destination.buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        }
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

        revealRootTab("设置", legacyID: "tabs.legacy.settings").tap()
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
        let home = revealRootTab("主页", legacyID: "tabs.legacy.home")
        home.tap()
        XCTAssertGreaterThan(assertCurrentBook("剑来").frame.height, 250)
        capture("22-classic-retained")

        revealRootTab("设置", legacyID: "tabs.legacy.settings").tap()
        if !forest.isHittable { themes.swipeUp() }
        XCTAssertTrue(forest.waitForExistence(timeout: 5)); forest.tap()
        home.tap()
        XCTAssertLessThan(assertCurrentBook("剑来").frame.height, 215)
        revealRootTab("寻书", legacyID: "tabs.legacy.discover").tap()
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
        let home = revealRootTab("主页", legacyID: "tabs.legacy.home")
        // The push animation still owns the bar for a few frames; wait for the
        // settle instead of sampling a mid-transition value or adding a delay.
        let homeInteractive = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == YES"), object: home)
        let outcome = XCTWaiter.wait(for: [homeInteractive], timeout: 5)
        if outcome != .completed {
            let legacy = app.buttons["tabs.legacy.home"]
            let native = app.buttons["主页"].firstMatch
            let line = [
                "legacy.exists=\(legacy.exists)",
                "legacy.hittable=\(legacy.isHittable)",
                "legacy.frame=\(legacy.frame)",
                "native.hittable=\(native.isHittable)",
                "native.frame=\(native.frame)",
                "tabBars=\(app.tabBars.count)",
                "hittableTabBars=\(app.tabBars.allElementsBoundByIndex.filter(\.isHittable).count)",
                "detailTitle=\(element("bookDetail.title").frame)",
                "app.frame=\(app.frame)"
            ].joined(separator: " | ")
            print("DIAG_DETAIL_TABBAR >>> \(line)")
            XCTContext.runActivity(named: "detail-tabbar-evidence") { activity in
                activity.add(XCTAttachment(string: line))
            }
        }
        XCTAssertEqual(outcome, .completed,
                       "The main bar stays visible on a normal detail")
        let lastChapter = app.buttons["山中来信"].firstMatch
        if !lastChapter.isHittable { element("bookDetail.scroll").swipeUp() }
        XCTAssertTrue(lastChapter.isHittable, "The last chapter can scroll fully above the bar")
        XCTAssertLessThanOrEqual(lastChapter.frame.maxY, home.frame.minY)
        capture("14-overflow-to-detail")

        let settings = revealRootTab("设置", legacyID: "tabs.legacy.settings")
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
        XCTAssertTrue(surface.frame.intersects(saved.frame),
                      "The saved paragraph must be in the actual viewport; surface=\(surface.frame); saved=\(saved.frame); \(element("reader.navigationEvidence").label)")
        XCTAssertFalse(rootTab("主页", legacyID: "tabs.legacy.home").isHittable)
        capture("17-restored-paragraph")
        surface.swipeUp()
        surface.swipeDown()
        XCTAssertTrue(surface.isHittable)
        returnFromReader()
        XCTAssertTrue(rootTab("主页", legacyID: "tabs.legacy.home").isHittable)
    }

    /// 热续读：同一本书返回后立刻再进入，必须复用停放的文档。会话身份、
    /// shell 加载次数和真实视口位置都应保持不变，并且不再出现开书骨架页。
    /// 这三条同时成立才能证明"直接进入正文"，只看正文出现会被重新加载骗过。
    func testReopeningTheSameBookReusesTheParkedDocumentInTheRealApp() throws {
        try launch(theme: "classic", fixture: "--desk-resume-paragraph")
        let entry = assertCurrentBook("剑来")
        entry.tap()
        let surface = element("reader.webScrollSurface")
        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        let saved = app.webViews.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "【已保存的阅读段落】")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        let evidence = element("reader.navigationEvidence")
        XCTAssertTrue(evidence.waitForExistence(timeout: 5))
        let firstSession = sessionIdentity(in: evidence.value as? String)
        XCTAssertNotNil(firstSession, "会话证据必须可解析：\(evidence.value as? String ?? "unavailable")")
        XCTAssertTrue((evidence.value as? String)?.contains("loads=1") == true)

        returnFromReader()
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        XCTAssertTrue(entry.isHittable)

        entry.tap()
        XCTAssertTrue(surface.waitForExistence(timeout: 8), "停放的文档必须直接回到屏上")
        XCTAssertFalse(element("reader.openingTitle").exists,
                       "已经就绪的正文不允许再出现开书骨架页：\(evidence.value as? String ?? "unavailable")")
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = evidence.value as? String else { return false }
            return self.sessionIdentity(in: value) == firstSession
                && value.contains("phase=reading") && value.contains("loads=1")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 8), .completed,
                       "重开必须复用同一个会话而不是重建：\(evidence.value as? String ?? "unavailable")")
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(surface.frame.intersects(saved.frame), "复用的文档必须仍停在已保存的段落")
        capture("27-parked-reader-reopened")
        returnFromReader()
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
    }

    /// `reader.navigationEvidence` 的 value 形如 `session=<uuid>;phase=...`。
    private func sessionIdentity(in evidence: String?) -> String? {
        guard let evidence else { return nil }
        return evidence.split(separator: ";").first { $0.hasPrefix("session=") }.map(String.init)
    }

    /// 详情入口（`reader|<id>`）的封面宿主必须全程只创建一次。详情 → 阅读 →
    /// 返回 → 再阅读，5 轮里如果 created 涨到 2，就是返回时封面被销毁重建，
    /// 真机表现正是「书本回到原位要重新加载一下」。
    func testDetailCoverSourceSurvivesRepeatedReaderRoundTrips() throws {
        try launch(theme: "classic", fixture: "--desk-first-reading")
        let cover = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "bookshelf.grid.", "月亮与六便士")).firstMatch
        if !cover.isHittable { app.swipeUp() }
        XCTAssertTrue(cover.isHittable)
        cover.tap()
        let read = app.buttons["bookDetail.read"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))

        var creations: [Int] = []
        var deaths: [Int] = []
        for cycle in 1...5 {
            read.tap()
            let surface = element("reader.webScrollSurface")
            XCTAssertTrue(surface.waitForExistence(timeout: 15), "第 \(cycle) 轮必须打开正文")
            let evidence = element("reader.navigationEvidence")
            XCTAssertTrue(evidence.waitForExistence(timeout: 5))
            let label = evidence.label
            let detailHost = detailCoverHost(in: label)
            XCTAssertNotNil(detailHost, "第 \(cycle) 轮读不到 reader| 封面宿主：\(label)")
            if let host = detailHost {
                creations.append(host.created)
                deaths.append(host.alive)
            }
            returnFromReader()
            XCTAssertTrue(read.waitForExistence(timeout: 10), "第 \(cycle) 轮必须回到详情")
        }
        XCTAssertEqual(Set(creations), [1],
                       "详情入口封面宿主 5 轮只能创建一次，实际序列：\(creations)")
        XCTAssertEqual(deaths.filter { $0 < 1 }.count, 0,
                       "详情入口封面宿主不得在返回时失效：\(deaths)")
        capture("28-detail-cover-survived")
    }

    /// 从 `coverHosts=<id>=created/alive,...` 里取详情入口（`reader|`）那一条。
    private func detailCoverHost(in label: String) -> (created: Int, alive: Int)? {
        guard let field = label.split(separator: ";").first(where: { $0.hasPrefix("coverHosts=") })
        else { return nil }
        for raw in field.dropFirst("coverHosts=".count).split(separator: ",") {
            guard let token = raw.split(separator: " ").first,
                  token.hasPrefix("reader|"),
                  let equals = token.lastIndex(of: "=") else { continue }
            let counts = token[token.index(after: equals)...].split(separator: "/")
            guard counts.count == 2,
                  let created = Int(counts[0].prefix(while: \.isNumber)),
                  let alive = Int(counts[1].prefix(while: \.isNumber)) else { continue }
            return (created, alive)
        }
        return nil
    }

    func testReaderReturnPreservesScrolledShelfAndSettingsStack() throws {
        try launch(theme: "classic", fixture: "--desk-shelf-scroll")
        let home = revealRootTab("主页", legacyID: "tabs.legacy.home")
        revealRootTab("设置", legacyID: "tabs.legacy.settings").tap()
        let appearance = app.buttons["外观"].firstMatch
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        appearance.tap()
        let appearanceBar = app.navigationBars["外观"]
        XCTAssertTrue(appearanceBar.waitForExistence(timeout: 5))
        home.tap()

        let title = "书架回归第12册"
        let cover = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "bookshelf.grid.", title)).firstMatch
        XCTAssertFalse(cover.isHittable, "The fixture must start with its target below the fold")
        let scrollStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.76))
        let scrollEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38))
        for _ in 0..<8 where !cover.isHittable {
            scrollStart.press(forDuration: 0.05, thenDragTo: scrollEnd, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(cover.isHittable, "Reach the real shelf cover by scrolling")
        let origin = cover.frame
        cover.tap()
        let detail = element("bookDetail.title")
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertEqual(detail.label, title)
        let read = app.buttons["bookDetail.read"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        read.tap()
        assertReaderProse()
        returnFromReader()
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertEqual(detail.label, title, "Return to the owning detail, not a new home stack")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == YES"), object: cover)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
        XCTAssertEqual(cover.frame.midY, origin.midY, accuracy: 8, "The same scrolled shelf row must return to its slot")
        // iOS 26 can keep the selected Home icon and Search in separate
        // circles after scrolling. The expanded Home query isn't reliable in
        // that layout. Check the surviving search control before any gesture.
        let returnedHome = rootTab("主页", legacyID: "tabs.legacy.home")
        if !returnedHome.isHittable {
            guard #available(iOS 26.0, *) else {
                XCTFail("The home tab must be tappable on return")
                return
            }
            XCTAssertTrue(globalSearchButton().isHittable, "The collapsed native navigation must already be usable on return")
        }
        capture("reader-return-scrolled-shelf")
        if #available(iOS 26.0, *) {
            let revealNavigation = app.buttons["bookshelf.revealChrome"]
            XCTAssertTrue(revealNavigation.isHittable, "The deep shelf must provide a way to restore navigation")
            revealNavigation.tap()
        }
        let settings = rootTab("设置", legacyID: "tabs.legacy.settings")
        let restoredHome = rootTab("主页", legacyID: "tabs.legacy.home")
        XCTAssertTrue(restoredHome.isHittable, "The home tab must be tappable after expanding the native bar")
        let settingsReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == YES"), object: settings)
        XCTAssertEqual(XCTWaiter.wait(for: [settingsReady], timeout: 3), .completed,
                       "The restored bar must support switching to the retained settings stack")
        settings.tap()
        XCTAssertTrue(appearanceBar.waitForExistence(timeout: 5), "Reader navigation must not reset another tab's stack")
    }

    func testReadingDeskReaderAndReturnInTheRealApp() throws {
        try launch(theme: "classic")
        let pager = element("bookshelf.readingPager")
        let entry = assertCurrentBook("剑来")
        XCTAssertTrue(entry.isHittable); entry.tap()
        assertReaderProse()
        returnFromReader()
        XCTAssertTrue(pager.waitForExistence(timeout: 3))
        let home = revealRootTab("主页", legacyID: "tabs.legacy.home")
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
        // 用户录屏：主体已恢复约 0.9 s 后「主页」才出现。只断言 cover 可点
        // 会把「导航栏还藏着」也算通过，所以直接读真实 UINavigationBar。
        // 不等待、不复试：返回结束后的第一帧就必须已经是恢复态。
        // 探针可能同时看到外层阅读栈（bar 故意隐藏），所以判定条件是
        // 「存在一条可见且已经显示 主页 的栏」，不是「第一条栏」。
        let chrome = element("bookshelf.chromeEvidence")
        XCTAssertTrue(chrome.waitForExistence(timeout: 2))
        let value = (chrome.value as? String) ?? "missing"
        XCTAssertFalse(value.contains("noNavigation"), value)
        XCTAssertTrue(value.contains("visibleHome=true"),
                      "返回结束后第一帧必须已有可见导航栏显示 主页（含 .large）：\(value)")
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
        let evidence = element("reader.navigationEvidence")
        let firstSession = try XCTUnwrap(sessionIdentity(in: evidence.value as? String))
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
        let reopened = try XCTUnwrap(evidence.value as? String)
        XCTAssertEqual(sessionIdentity(in: reopened), firstSession, "Crossing chapters must not replace the parked session")
        XCTAssertTrue(reopened.contains("web=1;loads=1"), "Reopening must keep the original WebView and document: \(reopened)")
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
        if outcome != .completed {
            let prose = app.webViews.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "【连续章\(chapter)·")).allElementsBoundByIndex
            let line = [
                "heading=\(heading.label)",
                "viewport=\(element("reader.webScrollSurface").frame)",
                "evidence=\(element("reader.navigationEvidence").value as? String ?? "-")",
                "proseCount=\(prose.count)",
                "prose=\(prose.prefix(4).map { "\($0.label.prefix(10))@\($0.frame)" }.joined(separator: ","))"
            ].joined(separator: " | ")
            print("DIAG_CROSS_CHAPTER \(chapter) >>> \(line)")
            XCTContext.runActivity(named: "cross-chapter-\(chapter)-viewport") { activity in
                activity.add(XCTAttachment(string: line))
            }
            capture("cross-chapter-failure-\(chapter)")
        }
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

    func testReaderShortDefaultSpeedEdgeDragCancels() throws {
        try verifyNativeReturn(reducesMotion: false, velocity: .default)
    }

    func testReaderFastNativeReturnCompletesFromProse() throws {
        try launch(theme: "classic", fixture: "--desk-resume-paragraph")
        let entry = assertCurrentBook("剑来")
        entry.tap()
        let surface = element("reader.webScrollSurface")
        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        let evidence = element("reader.navigationEvidence")
        let saved = app.webViews.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "【已保存的阅读段落】")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 45), "Wait for real prose before injecting the edge gesture")
        XCTAssertTrue(surface.frame.intersects(saved.frame))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = (evidence.value as? String) ?? ""
            let label = evidence.label
            return value.contains("phase=reading") && value.contains("presented=true")
                && label.contains("transition=false") && label.contains("priority=resolved")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed,
                       "The real reader must acknowledge prose; \(evidence.exists ? evidence.label : "reader missing")")
        let readyPosition = evidence.value as? String
        let previousSession = sessionIdentity(in: readyPosition)
        XCTAssertNotNil(previousSession)
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.008, dy: 0.52))
        // Use the same default-speed long stroke that passed after a cancelled
        // drag on iOS 16.4. A short hold lets CoreSimulator deliver the end
        // sample before lifting; completion must still occur on this first drag.
        edge.press(forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.52)),
            withVelocity: .default, thenHoldForDuration: 0.4)
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == YES"), object: entry)
        let outcome = XCTWaiter.wait(for: [restored], timeout: 5)
        if outcome != .completed { capture("reader-fast-native-return-failure") }
        XCTAssertEqual(outcome, .completed,
            "A fast native edge return must reveal the retained home; initial=\(readyPosition ?? "nil"); \(evidence.exists ? evidence.label : "reader closed")")
        XCTAssertTrue(rootTab("主页", legacyID: "tabs.legacy.home").isHittable)
        entry.tap()
        let reopened = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == YES"), object: surface)
        XCTAssertEqual(XCTWaiter.wait(for: [reopened], timeout: 10), .completed,
                       "The first tap after returning must reopen the reader")
        let reopenedSession = evidence.value as? String
        XCTAssertEqual(sessionIdentity(in: reopenedSession), previousSession, "Return must retain the already loaded reader")
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.52))
        center.press(forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.52)),
            withVelocity: .default, thenHoldForDuration: 0.4)
        XCTAssertTrue(surface.isHittable, "A horizontal pan that starts inside the prose must not leave the reader")
        XCTAssertEqual(evidence.value as? String, reopenedSession)
        capture("reader-fast-native-return-reopened")
    }

    func testReaderSystemReturnCanCancelWithReducedMotion() throws {
        try verifyNativeReturn(reducesMotion: true)
    }

    func testNativeReturnCancellationWithLongerSubthresholdDrag() throws {
        try verifyNativeReturn(reducesMotion: false, cancelFraction: 0.20)
    }

    func testNativeReturnCancellationWithImmediateSlowDrag() throws {
        try verifyNativeReturn(reducesMotion: false, cancelFraction: 0.20, pressDuration: 0.05)
    }

    func testNativeReturnCancellationWithImmediateDefaultDrag() throws {
        // The older native driver projects default-speed input farther even
        // after the stationary XCTest hold. Keep a measurable short stroke
        // outside the recognition dead zone, not near its projected midpoint.
        let defaultCancelFraction: CGFloat = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 0.20 : 0.12
        try verifyNativeReturn(reducesMotion: false, cancelFraction: defaultCancelFraction, pressDuration: 0.05, velocity: .default)
    }

    private func verifyNativeReturn(reducesMotion: Bool, cancelFraction: CGFloat = 0.13,
                                    pressDuration: TimeInterval = 0.05, velocity: XCUIGestureVelocity = .slow) throws {
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
        let sessionEvidence = element("reader.navigationEvidence")
        XCTAssertTrue(sessionEvidence.waitForExistence(timeout: 5))
        let sessionBefore = sessionEvidence.value as? String
        XCTAssertTrue(sessionBefore?.contains("web=1;loads=1") == true)
        let motionBefore = Int((nativeEvidence.value as? String) ?? "") ?? (-1)
        XCTAssertGreaterThanOrEqual(motionBefore, 0)
        print("BOOK_NATIVE_CANCEL_BEFORE distance=\(cancelFraction) speed=\(velocity) \(nativeEvidence.label)")
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.008, dy: 0.52))
        // Let the document settle before synthesizing the edge drag; an
        // in-flight mount can swallow the first touch sequence.
        Thread.sleep(forTimeInterval: 0.4)
        // Paired runs show the 0.2 s stationary press never starts UIKit's
        // return, while 0.05 s starts and cancels with both slow/default drags.
        // Keep the motion assertion: an ignored gesture is not cancellation.
        edge.press(forDuration: pressDuration,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: cancelFraction, dy: 0.52)),
            withVelocity: velocity, thenHoldForDuration: 0.8)
        if !surface.isHittable { capture("reader-native-cancellation-failure") }
        XCTAssertTrue(surface.isHittable, "Cancel must keep the same real reader active")
        XCTAssertTrue(saved.exists && surface.frame.intersects(saved.frame))
        XCTAssertFalse(rootTab("主页", legacyID: "tabs.legacy.home").isHittable)
        let motionAfter = Int((nativeEvidence.value as? String) ?? "") ?? (-1)
        print("BOOK_NATIVE_CANCEL_AFTER \(sessionEvidence.label) \(nativeEvidence.label)")
        XCTAssertGreaterThan(motionAfter, motionBefore,
                             "A real native gesture must move; an ignored drag is not cancellation; \(sessionEvidence.label)")
        XCTAssertTrue(sessionEvidence.label.contains("native-pop:cancelled"),
            "UIKit must report cancellation, not just a stationary reader; \(sessionEvidence.label)")
        XCTAssertEqual(sessionEvidence.value as? String, sessionBefore,
                       "Cancellation must retain the same presentation and one shell load")
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
        try launch(theme: "shuimo")
        capture("07-shuimo-home")
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
        // 「减少 App 动态效果」已从 App 删除。「下一本最近阅读」步进器是它的
        // 降级形态：动效不可关 → 翻页书台恒在 → 步进器不再出现。
        // 这段只保留深色主题取证，不再断言已删除的形态。
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
        for theme in ["kleinSage", "wuxia", "anime"] {
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

    private func launch(theme: String?, mode: String = "light", reducesMotion: Bool = false, fixture: String? = nil,
                        shelfQuery: String? = nil, extraArguments: [String] = []) throws {
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
        if fixture == "--desk-resume-paragraph" { app.launchArguments.append("--reader-edge-input-trace") }
        app.launchArguments += extraArguments
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
        if legacy.exists { return legacy }
        // iOS 26's native tab buttons carry the SF Symbol as their identifier
        // (`house`, `books.vertical`, `gearshape`, `magnifyingglass`), not the
        // legacy id. Matching by label alone is ambiguous on a pushed screen:
        // the navigation Back button is also labelled with the parent title
        // ("主页"), so `app.buttons["主页"]` resolves to Back, and any hittability
        // assertion then measures the Back button instead of the tab. Pin the
        // known identifiers first, and only fall back to a label query that
        // excludes the back button.
        let nativeIdentifiers = ["主页": "house", "寻书": "books.vertical",
                                 "设置": "gearshape", "搜索": "magnifyingglass"]
        if let identifier = nativeIdentifiers[label] {
            let native = app.buttons[identifier]
            if native.exists { return native }
        }
        let notBack = app.buttons.matching(
            NSPredicate(format: "label == %@ AND identifier != %@", label, "BackButton"))
        return notBack.firstMatch
    }

    /// Expanding the collapsed iOS 26 tab bar is only ever legitimate while the
    /// shelf owns the screen. Inside the reader the same gestures would tap a
    /// hidden control or scroll the prose, and the reader tests assert that the
    /// tab bar is NOT reachable there. Callers that need to switch tabs say so
    /// explicitly; a getter must never mutate the screen it is measuring.
    @discardableResult
    private func revealRootTab(_ label: String, legacyID: String) -> XCUIElement {
        let tab = rootTab(label, legacyID: legacyID)
        if tab.exists && tab.isHittable { return tab }
        XCTAssertFalse(element("reader.webScrollSurface").exists,
                       "Refusing to expand the tab bar from inside the reader")
        // iOS 26 collapses the native bar to the selected tab plus search once
        // the content scrolls. Tapping that capsule is the system's own expand
        // gesture; a downward scroll in the owning surface also restores it.
        // Neither is allowed to run inside the reader, where it would scroll
        // the prose the caller is measuring.
        let selected = app.buttons.matching(NSPredicate(format: "value CONTAINS %@", "Selected")).firstMatch
        if selected.exists && selected.isHittable {
            selected.tap()
        }
        // Only the shelf owns the collapse gesture. On a pushed detail the
        // system keeps the bar; scrolling there would collapse it again and the
        // caller's "bar stays visible" assertion would never recover.
        if element("bookshelf.readingPager").exists {
            element("bookshelf.readingPager").swipeDown()
        }
        _ = tab.waitForExistence(timeout: 3)
        return tab
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
        // 阅读器现在是覆盖层，退出要等它真正卸载，而不是同步返回。
        // 这是真实交互路径（点阅读器自己的返回按钮），不是绕过手势。
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == NO"),
            object: element("reader.webScrollSurface"))
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed,
                       "覆盖层必须在返回后真正卸载")
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
