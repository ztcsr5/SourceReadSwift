import XCTest

final class ForestFollowupUITests: XCTestCase {
    func testGridAndListOpenProseAndStillOfferDetailsOnHold() throws {
        continueAfterFailure = false
        let app = try launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["bookshelf.filters"].waitForExistence(timeout: 6))
        let switchToGrid = app.buttons["切换为网格视图"]
        if switchToGrid.exists { switchToGrid.tap() }
        for prefix in ["bookshelf.grid.", "bookshelf.list."] {
            let book = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                prefix, "剑来")).firstMatch
            for _ in 0..<4 where !book.isHittable { app.swipeUp() }
            XCTAssertTrue(book.isHittable)
            book.tap()
            assertProse(app)
            returnFromReader(app)
            XCTAssertTrue(book.isHittable)
            capture(app, name: prefix == "bookshelf.grid." ? "forest-direct-grid-return" : "forest-direct-list-return")
            book.press(forDuration: 0.8)
            let details = app.buttons["书籍详情"].firstMatch
            XCTAssertTrue(details.waitForExistence(timeout: 4))
            details.tap()
            XCTAssertTrue(app.staticTexts["bookDetail.title"].waitForExistence(timeout: 5))
            app.navigationBars.buttons.element(boundBy: 0).tap()
            if prefix == "bookshelf.grid." {
                let toggle = app.buttons["切换为列表视图"]
                XCTAssertTrue(toggle.isHittable)
                toggle.tap()
            }
        }
    }

    func testDetailReaderReturnImmediatelyAllowsOwnerBackNavigation() throws {
        continueAfterFailure = false
        let app = try launch()
        defer { app.terminate() }
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "bookshelf.continue.", "剑来")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 6))
        entry.press(forDuration: 0.8)
        app.buttons["书籍详情"].firstMatch.tap()
        let read = app.buttons["bookDetail.read"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        read.tap()
        assertProse(app)
        returnFromReader(app)
        XCTAssertTrue(read.isHittable, "No post-return delay may keep the owning detail locked")
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        edge.press(forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)),
            withVelocity: .fast, thenHoldForDuration: 0.02)
        XCTAssertTrue(entry.isHittable, "The next edge gesture must return from detail without a second attempt")
        capture(app, name: "forest-immediate-detail-back")
    }

    func testSettingsOrderAboutPageAndSourceToolsRemainReachable() throws {
        continueAfterFailure = false
        let app = try launch(fixture: "--reader-preview-regression")
        defer { app.terminate() }
        tab(app, title: "设置", legacy: "tabs.legacy.settings").tap()
        XCTAssertFalse(app.buttons["settings.aiAssistant"].exists)
        capture(app, name: "forest-settings-order")
        let sources = app.buttons["书源管理"].firstMatch
        for _ in 0..<3 where !sources.isHittable { app.swipeUp() }
        sources.tap()
        XCTAssertTrue(app.navigationBars["书源管理"].waitForExistence(timeout: 5))
        let tools = app.buttons["书源工具"].firstMatch
        if !app.buttons["settings.aiAssistant"].isHittable {
            (tools.exists ? tools : app.descendants(matching: .any)["sources.tools"].firstMatch).tap()
        }
        let sourceToolsReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons["settings.aiAssistant"].isHittable && app.buttons["settings.webSourceWriting"].isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [sourceToolsReady], timeout: 5), .completed,
            "Wait for the disclosure layout to expose both source tools")
        XCTAssertTrue(app.buttons["settings.aiAssistant"].isHittable)
        XCTAssertTrue(app.buttons["settings.webSourceWriting"].isHittable)
        XCTAssertTrue(app.buttons["sources.import"].isHittable)
        app.buttons["sources.options"].tap()
        XCTAssertTrue(app.buttons["批量管理"].waitForExistence(timeout: 4))
        app.buttons["批量管理"].tap()
        XCTAssertTrue(app.buttons["完成"].isHittable)
        app.buttons["完成"].tap()
        capture(app, name: "forest-source-management")
        app.buttons["sources.import"].tap()
        XCTAssertTrue(app.navigationBars["导入源"].waitForExistence(timeout: 4))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).press(forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)),
            withVelocity: .fast, thenHoldForDuration: 0.02)
        XCTAssertTrue(app.navigationBars["书源管理"].waitForExistence(timeout: 4))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let about = app.buttons["settings.about"]
        for _ in 0..<5 where !about.isHittable { app.swipeUp() }
        about.tap()
        XCTAssertTrue(app.staticTexts["纸，是故事停留的地方。\n间，是留给自己的片刻。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["致谢与声明"].exists)
        XCTAssertFalse(app.staticTexts["交流与反馈"].exists)
        capture(app, name: "forest-about-name")
        app.buttons["about.options"].tap()
        app.buttons["让阅读按你的习惯来"].tap()
        XCTAssertTrue(app.navigationBars["让阅读按你的习惯来"].waitForExistence(timeout: 4))
    }

    func testJournalButtonAndReturningFromBackgroundRemainInteractive() throws {
        continueAfterFailure = false
        let app = try launch(theme: "coverGlass", presentation: "journal")
        defer { app.terminate() }
        let button = app.buttons["继续阅读"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 6))
        capture(app, name: "cover-glass-readable-journal-button")
        for _ in 0..<2 {
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(button.isHittable)
        }
        button.tap()
        assertProse(app)
    }

    private func launch(theme: String = "forest", presentation: String = "classic",
                        fixture: String = "--floating-desk-regression") throws -> XCUIApplication {
        let app = XCUIApplication()
        let cover = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "jianlai-cover", withExtension: "jpg"))
        app.launchEnvironment["SOURCEREAD_UI_COVER_JPEG"] = try Data(contentsOf: cover).base64EncodedString()
        app.launchArguments = [fixture, "-settings.visualTheme", theme,
            "-settings.homeBookPresentation", presentation, "-settings.themeMode", "light",
            "-reader.mode", "scroll", "-settings.reducesMotion", "NO"]
        app.launch()
        return app
    }

    private func assertProse(_ app: XCUIApplication) {
        XCTAssertTrue(app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            "这是纸间的隔离视觉验证书库")).firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["bookDetail.read"].isHittable)
    }

    private func returnFromReader(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5)).press(forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)),
            withVelocity: .fast, thenHoldForDuration: 0.02)
    }

    private func tab(_ app: XCUIApplication, title: String, legacy: String) -> XCUIElement {
        app.buttons[legacy].exists ? app.buttons[legacy] : app.tabBars.buttons[title]
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
