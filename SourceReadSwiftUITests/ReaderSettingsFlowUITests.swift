import XCTest
import CoreGraphics

final class ReaderSettingsFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
    }

    func testTwoConsecutiveSettingsVisitsStayInTheRealReader() {
        launchReader(mode: "scroll")
        for route in ["typography", "appearance"] {
            openSettings()
            if route == "typography" {
                element("reader.settings.bookTitle").tap()
                assertPanelRemainsOpen("header-whitespace")
            }
            let link = element("reader.settings.route." + route)
            XCTAssertTrue(link.waitForExistence(timeout: 5))
            link.tap()
            assertPanelRemainsOpen(route)
            let close = element("reader.settings.close")
            XCTAssertTrue(close.isHittable, "Settings must retain a visible, local close control")
            close.tap()
            XCTAssertTrue(element("reader.openSettings").waitForExistence(timeout: 3))
            XCTAssertFalse(shelfEntry.isHittable, "Closing settings must not return to the shelf")
            capture("reader-menu-real-" + route)
        }
    }

    func testSearchPreviewOpensDirectlyAndOffersToKeepReadingPositionOnExit() {
        app.launchArguments = ["--reader-preview-regression", "-reader.mode", "scroll"]
        app.launch()
        let legacy = app.buttons["tabs.legacy.discover"]
        let discover = legacy.exists ? legacy : app.tabBars.buttons["寻书"]
        XCTAssertTrue(discover.waitForExistence(timeout: 5)); discover.tap()
        let search = app.textFields["搜索书名或作者"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Preview\n")
        let result = app.staticTexts["Preview · 未入架阅读样本"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10)); result.tap()
        let read = element("bookDetail.read")
        XCTAssertTrue(read.waitForExistence(timeout: 6)); read.tap()
        let surface = element("reader.webScrollSurface")
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in surface.isHittable && !self.element("reader.openingProgress").exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landed], timeout: 12), .completed)
        XCTAssertFalse(element("bookTitlePage.read").exists, "The detail action opens the reader without a second start button")
        let prose = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "【试读段落1】")).firstMatch
        XCTAssertTrue(prose.waitForExistence(timeout: 8) && surface.frame.intersects(prose.frame), "Preview must reach real visible prose")
        revealMenu()
        element("reader.returnToShelf").tap()
        let prompt = app.buttons["暂不加入"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5), "A successful preview must offer shelf membership on return")
        prompt.tap()
        XCTAssertTrue(read.isHittable)
        XCTAssertEqual(element("bookDetail.title").label, "Preview · 未入架阅读样本")
    }

    func testDiscoverAddAppearsOnFirstHomeReturnAndNoticeExpires() {
        app.launchArguments = ["--reader-preview-regression", "-discover.resultLayout", "list",
            "-bookshelf.isGridMode", "YES", "-settings.visualTheme", "forest"]
        app.launch()
        let home = tab("主页", symbol: "house", legacyID: "tabs.legacy.home")
        let discover = tab("寻书", symbol: "books.vertical", legacyID: "tabs.legacy.discover")
        XCTAssertTrue(home.waitForExistence(timeout: 6))
        discover.tap()
        let search = app.textFields["搜索书名或作者"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Preview\n")
        let addToShelf = element("discover.addToShelf")
        XCTAssertTrue(addToShelf.waitForExistence(timeout: 10))
        addToShelf.tap()
        let confirm = app.buttons.matching(NSPredicate(
            format: "label == %@ AND identifier != %@", "加入书架", "discover.addToShelf")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let notice = element("discover.shelfAddNotice")
        XCTAssertTrue(notice.waitForExistence(timeout: 4))
        XCTAssertEqual(notice.label, "已加入书架")
        let noticeDismissed = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            !element("discover.shelfAddNotice").exists
        }, object: nil)
        let result = XCTWaiter.wait(for: [noticeDismissed], timeout: 4)
        if result != .completed { capture("discover-shelf-notice-did-not-dismiss") }
        XCTAssertEqual(result, .completed)

        home.tap()
        let shelfRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@",
            "bookshelf.grid.https://preview-fixture.invalid|", "bookshelf.list.https://preview-fixture.invalid|")).firstMatch
        XCTAssertTrue(shelfRow.waitForExistence(timeout: 4),
                      "Home was already mounted; the first tab return must show the addition")
        shelfRow.tap()
        XCTAssertTrue(element("bookDetail.title").waitForExistence(timeout: 5),
                      "A shelf row still opens book detail, not prose")
    }

    func testSettingsPaperAndSubpageChangesKeepOneReader() {
        launchReader(mode: "scroll", pinsPaper: false, skin: "wuxia")
        openSettings()
        let evidence = element("reader.navigationEvidence")
        let initialSession = (evidence.value as? String)?.split(separator: ";").first
        XCTAssertNotNil(initialSession)
        for name in ["极黑", "素白", "极黑", "素白"] {
            let swatch = app.buttons[name].firstMatch
            XCTAssertTrue(swatch.waitForExistence(timeout: 4) && swatch.isHittable)
            swatch.tap()
            XCTAssertTrue(swatch.isSelected)
            let section = element("reader.settings.route.typography")
            XCTAssertTrue(section.isHittable)
            section.tap()
            let back = element("reader.settings.back")
            XCTAssertTrue(back.waitForExistence(timeout: 4) && back.isHittable)
            back.tap()
        }
        capture("reader-settings-after-repeated-paper-and-route-changes")
        element("reader.settings.close").tap()
        XCTAssertTrue(element("reader.returnToShelf").isHittable)
        XCTAssertEqual((evidence.value as? String)?.split(separator: ";").first, initialSession)
        XCTAssertTrue((evidence.value as? String)?.contains("web=1;loads=1") == true)
    }

    func testPagedReaderRetainsItsSettingsAndReadingSession() {
        launchReader(mode: "pageTurn")
        openSettings()
        element("reader.settings.route.typography").tap()
        assertPanelRemainsOpen("paged-typography")
        element("reader.settings.close").tap()
        XCTAssertTrue(element("reader.returnToShelf").isHittable)
        XCTAssertFalse(shelfEntry.isHittable)
    }

    func testKawaiiMenuAndChildRoutesStayOnTheSameReader() {
        launchReader(mode: "scroll", paper: "kawaiiNote", skin: "kawaii")
        openSettings()
        let current = element("reader.navigationEvidence")
        let session = (current.value as? String)?.split(separator: ";").first
        XCTAssertNotNil(session)
        capture("reader-edition-kawaii-workbench")
        element("reader.settings.route.typography").tap()
        XCTAssertTrue(element("reader.settings.back").isHittable)
        capture("reader-edition-kawaii-type")
        element("reader.settings.back").tap()
        XCTAssertTrue(element("reader.settings.route.typography").isHittable)
        element("reader.settings.close").tap()
        XCTAssertTrue(element("reader.openSettings").isHittable)
        XCTAssertEqual((current.value as? String)?.split(separator: ";").first, session)
        XCTAssertFalse(shelfEntry.isHittable)
    }

    func testCurlTurnsForwardAndBackWithoutLosingTextOrItsSettingsRoute() {
        launchReader(mode: "pageCurl")
        let appFrame = app.frame
        let center = CGPoint(x: appFrame.midX, y: appFrame.midY)
        func waitForVisiblePage(excluding previous: String = "", timeout: TimeInterval) -> String? {
            // Let XCTest match the changed prose in one snapshot. Calling
            // frame, hittability and value inside the waiter consumed its entire
            // deadline on a busy simulator even though the real curl finished.
            let changedProse = app.textViews.matching(
                NSPredicate(format: "value != nil AND value != %@ AND value != %@", "", previous)
            ).firstMatch
            guard changedProse.waitForExistence(timeout: timeout) else { return nil }
            XCTAssertTrue(changedProse.isHittable && changedProse.frame.contains(center),
                          "The changed prose must occupy the visible curl page")
            return changedProse.value as? String
        }
        guard let first = waitForVisiblePage(timeout: 12) else {
            return XCTFail("The curl must mount a real text page")
        }
        var previous = first
        for (turn, direction) in [1, 1, 1, -1, -1, -1].enumerated() {
            app.coordinate(withNormalizedOffset: CGVector(dx: direction > 0 ? 0.85 : 0.15, dy: 0.5)).tap()
            guard let landed = waitForVisiblePage(excluding: previous, timeout: 5) else {
                return XCTFail("A real curl page must change its rendered text on turn \(turn + 1)")
            }
            XCTAssertFalse(landed.isEmpty)
            XCTAssertNotEqual(landed, previous)
            previous = landed
            XCTAssertFalse(shelfEntry.isHittable)
        }
        XCTAssertEqual(previous, first, "Three reverse turns must return to the same original page")
        openSettings()
        element("reader.settings.close").tap()
        XCTAssertTrue(element("reader.returnToShelf").isHittable)
        capture("reader-curl-forward-back-restored")
    }

    func testTextSelectionStartsFromMoreAndReturnsToTheSameReader() {
        launchReader(mode: "scroll")
        let evidence = element("reader.navigationEvidence")
        let session = evidence.value as? String
        revealMenu()
        element("reader.more").tap()
        let select = app.buttons["选择文字"].firstMatch
        XCTAssertTrue(select.waitForExistence(timeout: 3))
        select.tap()
        let done = element("reader.selection.done")
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        XCTAssertTrue(done.isHittable)
        XCTAssertFalse(element("reader.openSettings").exists)
        capture("reader-selection-from-more")
        done.tap()
        XCTAssertTrue(element("reader.openSettings").waitForExistence(timeout: 3))
        XCTAssertEqual(evidence.value as? String, session)
        XCTAssertFalse(shelfEntry.isHittable)
    }

    func testNewPageEffectsTurnForwardAndBackToTheSameText() {
        for mode in ["dissolve", "stacked", "ripple"] {
            launchReader(mode: mode)
            let prose = app.textViews.matching(NSPredicate(format: "value != nil AND value != %@", "")).firstMatch
            XCTAssertTrue(prose.waitForExistence(timeout: 15))
            let first = prose.value as? String
            XCTAssertNotNil(first)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
            let next = app.textViews.matching(NSPredicate(format: "value != nil AND value != %@ AND value != %@", "", first ?? "")).firstMatch
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            XCTAssertTrue(next.isHittable)
            capture("reader-page-effect-" + mode)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
            let restored = app.textViews.matching(NSPredicate(format: "value == %@", first ?? "")).firstMatch
            XCTAssertTrue(restored.waitForExistence(timeout: 5))
            XCTAssertTrue(restored.isHittable)
            XCTAssertFalse(shelfEntry.isHittable)
            app.terminate()
        }
    }

    func testRepeatedNativeMoreMenuCancellationKeepsTheReaderAndSettingsUsable() {
        launchReader(mode: "scroll")
        revealMenu()
        let more = element("reader.more")
        for visit in 0..<6 {
            XCTAssertTrue(more.isHittable, "The native menu must remain reachable on visit \(visit)")
            more.tap()
            let details = app.buttons["书籍详情"].firstMatch
            XCTAssertTrue(details.waitForExistence(timeout: 3))
            XCTAssertTrue(details.isHittable)
            if visit == 0 || visit == 5 { capture("reader-more-open-\(visit)") }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: details)
            let dismissalResult = XCTWaiter.wait(for: [dismissed], timeout: 3)
            if dismissalResult != .completed {
                capture("reader-more-dismissal-failure-\(visit)")
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "reader-more-dismissal-hierarchy-\(visit)"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
            }
            XCTAssertEqual(dismissalResult, .completed, "Native menu cancellation failed on visit \(visit)")
            XCTAssertTrue(element("reader.openSettings").isHittable)
            XCTAssertFalse(shelfEntry.isHittable)
        }
        // An independent prose tap still dismisses the chrome once the menu is gone.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)).tap()
        let settings = element("reader.openSettings")
        let chromeHidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: settings)
        XCTAssertEqual(XCTWaiter.wait(for: [chromeHidden], timeout: 3), .completed)
        openSettings()
        element("reader.settings.close").tap()
        XCTAssertTrue(more.isHittable)
        element("reader.returnToShelf").tap()
        XCTAssertTrue(shelfEntry.waitForExistence(timeout: 3))
    }

    func testHeadingAndChromeReturnToSettingsNotTheBookshelf() {
        checkLocalReturn(routes: ["heading", "chrome"], paper: "bamboo")
    }

    func testBindingsAndAssistanceReturnToSettingsNotTheBookshelf() {
        checkLocalReturn(routes: ["themes", "assistance"], paper: "dark")
    }

    func testReturningToShelfRestoresBottomNavigationWithTheRoot() {
        launchReader(mode: "scroll")
        revealMenu()
        element("reader.returnToShelf").tap()
        XCTAssertTrue(shelfEntry.waitForExistence(timeout: 3))
        let rootReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.shelfEntry.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rootReady], timeout: 3), .completed)
        XCTAssertTrue(shelfEntry.isHittable)
        // Query immediately after the real root is ready, not after an arbitrary
        // five-second eventual-visibility window like the older placeholder test.
        let tabs = app.tabBars.firstMatch
        let home = tabs.exists ? tabs.buttons["主页"] : app.buttons["主页"]
        XCTAssertTrue(home.isHittable, "The home tab must return with the shelf, not later")
        capture("reader-returned-root")
    }

    private var shelfEntry: XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bookshelf.continue.")).firstMatch
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func checkLocalReturn(routes: [String], paper: String) {
        launchReader(mode: "scroll", paper: paper)
        openSettings()
        for route in routes {
            let link = element("reader.settings.route." + route)
            for _ in 0..<3 {
                if link.isHittable { break }
                element("reader.settingsWorkbench").scrollViews.firstMatch.swipeUp()
            }
            XCTAssertTrue(link.isHittable)
            link.tap()
            assertPanelRemainsOpen(paper + "-" + route)
            let back = element("reader.settings.back")
            XCTAssertTrue(back.isHittable)
            back.tap()
            XCTAssertTrue(element("reader.settings.route.typography").isHittable)
            XCTAssertFalse(shelfEntry.isHittable)
        }
    }

    private func launchReader(mode: String, paper: String = "white", pinsPaper: Bool = true, skin: String? = nil) {
        app.launchArguments = ["--reader-settings-regression", "-reader.mode", mode,
            "-reader.atelierEnabled", "YES",
            "-reader.menuSurfaceStyle", "system", "-reader.menuUsesWallpaper", "NO"]
        if pinsPaper { app.launchArguments += ["-reader.background", paper] }
        if let skin { app.launchArguments += ["-settings.visualTheme", skin] }
        app.launch()
        XCTAssertTrue(shelfEntry.waitForExistence(timeout: 10))
        shelfEntry.tap()
        guard mode == "scroll" else { return }
        let surface = element("reader.webScrollSurface")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            surface.isHittable && self.app.webViews.staticTexts.firstMatch.exists
                && !self.element("reader.openingProgress").exists
        }, object: nil)
        let outcome = XCTWaiter.wait(for: [ready], timeout: 10)
        if outcome != .completed { capture("reader-settings-prose-startup-failure") }
        XCTAssertEqual(outcome, .completed,
            "Actual prose not ready; recovery=\(element("reader.openingRecovery").exists); startup=\(surface.value ?? "unavailable"); navigation=\(element("reader.navigationEvidence").label); session=\(element("reader.navigationEvidence").value ?? "unavailable")")
    }

    private func tab(_ title: String, symbol: String, legacyID: String) -> XCUIElement {
        let legacy = app.buttons[legacyID]
        if legacy.exists { return legacy }
        let native = app.tabBars.buttons[symbol]
        return native.exists ? native : app.tabBars.buttons[title]
    }

    private func revealMenu() {
        let settings = element("reader.openSettings")
        if !settings.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)).tap()
        }
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "Menu input: \(element("reader.navigationEvidence").label)")
        XCTAssertTrue(settings.isHittable)
    }

    private func openSettings() {
        revealMenu()
        element("reader.openSettings").tap()
        XCTAssertTrue(element("reader.settingsWorkbench").waitForExistence(timeout: 3))
        capture("reader-settings-real-home")
    }

    private func assertPanelRemainsOpen(_ route: String) {
        let panel = element("reader.settingsWorkbench")
        let unexpectedlyClosed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: panel)
        XCTAssertEqual(XCTWaiter.wait(for: [unexpectedlyClosed], timeout: 1), .timedOut,
            "Entering a settings section must not dismiss the panel or pop the reader")
        capture("reader-settings-real-" + route)
    }

    private func capture(_ phase: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = phase
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
