import XCTest

final class LabJourneyTests: XCTestCase {
    @MainActor func testSixVideoScenesHomeDetailsSavedMoviesSearchAndReplay() throws {
        let app = XCUIApplication(); app.launchArguments = ["--lab-ui-testing"]; app.launch()
        let next = app.buttons["intro.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 12))
        for step in 0..<6 {
            let enabled = NSPredicate(format: "enabled == true")
            let ready = XCTNSPredicateExpectation(predicate: enabled, object: next)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
            addSnapshot("intro-live-\(step)", app: app)
            next.tap()
        }
        let detail = app.buttons["home.detail"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        addSnapshot("journey-home", app: app); detail.tap()
        let save = app.buttons["detail.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 8)); save.tap()
        XCTAssertTrue(app.buttons["已加入待看"].exists)
        addSnapshot("journey-detail-saved", app: app)
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.buttons["dock.1"].waitForExistence(timeout: 8)); app.buttons["dock.1"].tap()
        XCTAssertTrue(app.staticTexts["我的待看"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["shelf.item.106379"].exists)
        addSnapshot("journey-collection", app: app)
        app.buttons["dock.2"].tap()
        XCTAssertTrue(app.staticTexts["尚未连接资源"].waitForExistence(timeout: 5))
        app.buttons["home.search"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        app.searchFields.firstMatch.tap(); app.searchFields.firstMatch.typeText("Bluey-no-match")
        XCTAssertTrue(app.staticTexts["没有匹配的离线片目"].waitForExistence(timeout: 5))
        app.buttons["关闭"].tap(); app.buttons["dock.3"].tap()
        let replay = app.buttons["重播启动序章"]
        XCTAssertTrue(replay.waitForExistence(timeout: 5)); replay.tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        app.buttons["intro.skip"].tap()
        XCTAssertTrue(app.buttons["dock.0"].waitForExistence(timeout: 5))
    }

    @MainActor private func addSnapshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "motionlab-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
