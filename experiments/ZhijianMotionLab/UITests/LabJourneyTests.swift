import XCTest

final class LabJourneyTests: XCTestCase {
    @MainActor func testIntroToHomeReaderQuoteAndReplay() throws {
        let app = XCUIApplication(); app.launchArguments = ["--lab-ui-testing"]; app.launch()
        let next = app.buttons["intro.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 12))
        for _ in 0..<5 { next.tap() }
        let read = app.buttons["home.read"]
        XCTAssertTrue(read.waitForExistence(timeout: 8))
        addSnapshot("journey-home", app: app)
        read.tap()
        let quote = app.buttons["reader.quote.0"]
        XCTAssertTrue(quote.waitForExistence(timeout: 8)); quote.tap()
        addSnapshot("journey-saved-paragraph", app: app)
        app.buttons["reader.close"].tap()
        XCTAssertTrue(app.buttons["dock.1"].waitForExistence(timeout: 8)); app.buttons["dock.1"].tap()
        XCTAssertTrue(app.staticTexts["我的书笺"].waitForExistence(timeout: 5))
        addSnapshot("journey-collection", app: app)
        app.buttons["dock.2"].tap()
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
