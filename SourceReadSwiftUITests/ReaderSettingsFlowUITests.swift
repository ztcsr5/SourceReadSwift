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

    func testSearchPreviewHasATitlePageAndOffersToKeepReadingPositionOnExit() {
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
        let titleRead = element("bookTitlePage.read")
        XCTAssertTrue(titleRead.waitForExistence(timeout: 5)); titleRead.tap()
        let surface = element("reader.webScrollSurface")
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in surface.isHittable && !self.element("reader.openingProgress").exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landed], timeout: 12), .completed)
        revealMenu()
        element("reader.returnToShelf").tap()
        let prompt = app.buttons["暂不加入"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5), "A successful preview must offer shelf membership on return")
        prompt.tap()
        XCTAssertTrue(titleRead.isHittable)
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

    func testCurlTurnsForwardAndBackWithoutLosingTextOrItsSettingsRoute() {
        launchReader(mode: "pageCurl")
        func currentPageText() -> String? {
            let center = CGPoint(x: app.frame.midX, y: app.frame.midY)
            return app.textViews.allElementsBoundByIndex.first {
                $0.isHittable && $0.frame.contains(center)
            }?.value as? String
        }
        let opened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            currentPageText()?.isEmpty == false
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 12), .completed)
        guard let first = currentPageText() else { return XCTFail("The curl must mount a real text page") }
        var previous = first
        for direction in [1, 1, 1, -1, -1, -1] {
            app.coordinate(withNormalizedOffset: CGVector(dx: direction > 0 ? 0.85 : 0.15, dy: 0.5)).tap()
            let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let text = currentPageText() else { return false }
                return !text.isEmpty && text != previous
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 5), .completed,
                           "A real curl page must change its rendered text after each turn")
            previous = currentPageText() ?? ""
            XCTAssertFalse(shelfEntry.isHittable)
        }
        XCTAssertEqual(currentPageText(), first, "Three reverse turns must return to the same original page")
        openSettings()
        element("reader.settings.close").tap()
        XCTAssertTrue(element("reader.returnToShelf").isHittable)
        capture("reader-curl-forward-back-restored")
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
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 3), .completed)
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

    private func launchReader(mode: String, paper: String = "white") {
        app.launchArguments = ["--reader-settings-regression", "-reader.mode", mode,
            "-reader.atelierEnabled", "YES", "-reader.background", paper,
            "-reader.menuSurfaceStyle", "system", "-reader.menuUsesWallpaper", "NO"]
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
            "Actual prose not ready; recovery=\(element("reader.openingRecovery").exists); startup=\(surface.value ?? "unavailable")")
    }

    private func revealMenu() {
        let settings = element("reader.openSettings")
        if !settings.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)).tap()
        }
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
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
