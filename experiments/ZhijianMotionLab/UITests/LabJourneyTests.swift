import XCTest

final class LabJourneyTests: XCTestCase {
    @MainActor func testIntroCanSwipeForwardAndBackwardWithoutContinueButton() throws {
        let app = XCUIApplication(); app.launchArguments = ["--lab-ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["intro.continue"].waitForExistence(timeout: 12))
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["首页，由你定义"].waitForExistence(timeout: 3), "A left swipe must change the live intro scene")
        app.swipeRight()
        let firstTitle = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "正在来到眼前")).firstMatch
        XCTAssertTrue(firstTitle.waitForExistence(timeout: 3), "A right swipe must return to the opening scene")
    }

    @MainActor func testReadingJourneyUsesRealSwipesLiveControlsAndSavedQuotes() throws {
        let app = XCUIApplication(); app.launchArguments = ["--lab-ui-testing"]; app.launch()
        let next = app.buttons["intro.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 12)); XCTAssertTrue(next.isEnabled)
        addSnapshot("reading-intro-0", app: app)
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["首页，由你定义"].waitForExistence(timeout: 4))
        app.scrollViews["intro.shelfScroll"].swipeUp()
        XCTAssertTrue(app.staticTexts["我的书单"].isHittable)
        addSnapshot("reading-shelf-scrolled", app: app)
        app.swipeRight()
        XCTAssertTrue(app.staticTexts["想读的，正在来到眼前"].waitForExistence(timeout: 4))
        app.swipeLeft(); next.tap()
        let ticket = app.buttons["intro.ticket.0"]
        XCTAssertTrue(ticket.waitForExistence(timeout: 4)); ticket.tap()
        XCTAssertEqual(ticket.value as? String, "背面")
        XCTAssertEqual(app.buttons["intro.ticket.1"].value as? String, "正面")
        addSnapshot("reading-intro-2-live-ticket", app: app)
        app.swipeLeft()
        let chapter = app.buttons["intro.nextChapter"]
        XCTAssertTrue(chapter.waitForExistence(timeout: 4)); chapter.tap()
        XCTAssertTrue(app.staticTexts["样段 2 / 3"].waitForExistence(timeout: 4))
        addSnapshot("reading-intro-3-live-progress", app: app)
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["故事，不止一种格式"].waitForExistence(timeout: 4))
        addSnapshot("reading-intro-4", app: app)
        app.swipeLeft()
        let period = app.buttons["intro.stats.period"]
        XCTAssertTrue(period.waitForExistence(timeout: 4)); period.tap()
        XCTAssertTrue(app.staticTexts["本周阅读"].waitForExistence(timeout: 4))
        addSnapshot("reading-intro-5-live-chart", app: app)
        next.tap()
        let read = app.buttons["home.read"].firstMatch
        XCTAssertTrue(read.waitForExistence(timeout: 8))
        addSnapshot("reading-home", app: app); read.tap()
        let quote = app.buttons["reader.quote.0"]
        XCTAssertTrue(quote.waitForExistence(timeout: 8)); quote.tap()
        XCTAssertTrue(app.staticTexts["已收进我的书笺"].waitForExistence(timeout: 4))
        addSnapshot("reading-reader-saved", app: app)
        app.buttons["reader.close"].tap()
        app.buttons["home.detail"].firstMatch.tap()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 5))
        addSnapshot("reading-detail", app: app)
        app.buttons["detail.back"].tap(); app.buttons["dock.1"].tap()
        XCTAssertTrue(app.staticTexts["我的书笺"].waitForExistence(timeout: 5))
        let saved = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "这里是《三体》的阅读器交互体验页")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        addSnapshot("reading-collection", app: app)
        app.buttons["home.search"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        app.searchFields.firstMatch.tap(); app.searchFields.firstMatch.typeText("no-such-book")
        XCTAssertTrue(app.staticTexts["没有匹配的样本书籍"].waitForExistence(timeout: 5))
        app.buttons["关闭"].tap(); app.buttons["dock.2"].tap()
        let replay = app.buttons["重播启动序章"]
        XCTAssertTrue(replay.waitForExistence(timeout: 5)); replay.tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["intro.skip"].isHittable); app.buttons["intro.skip"].tap()
        XCTAssertTrue(app.buttons["dock.0"].waitForExistence(timeout: 5))
    }

    @MainActor private func addSnapshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "motionlab-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
