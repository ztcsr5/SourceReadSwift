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

    func testPagedReaderRetainsItsSettingsAndReadingSession() {
        launchReader(mode: "pageTurn")
        openSettings()
        element("reader.settings.route.typography").tap()
        assertPanelRemainsOpen("paged-typography")
        element("reader.settings.close").tap()
        XCTAssertTrue(element("reader.returnToShelf").isHittable)
        XCTAssertFalse(shelfEntry.isHittable)
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
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed,
            "Reveal the menu only after the actual prose is ready to receive a tap")
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
