import XCTest

final class ComicReaderFlowUITests: XCTestCase {
    func testComicDetailsOpenTheNativeStripAndRetainThePreviewReturnPath() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--comic-reader-regression"]
        app.launch()
        defer {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "comic-flow-final"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
        let legacy = app.buttons["tabs.legacy.discover"]
        let discover = legacy.exists ? legacy : app.tabBars.buttons["寻书"]
        XCTAssertTrue(discover.waitForExistence(timeout: 5))
        discover.tap()
        let search = app.textFields["搜索书名或作者"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Comic\n")
        let result = app.staticTexts["Comic · 图片阅读样本"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.tap()
        let read = element("bookDetail.read", in: app)
        XCTAssertTrue(read.waitForExistence(timeout: 8))
        read.tap()
        let strip = app.collectionViews["comic.stripSurface"]
        XCTAssertTrue(strip.waitForExistence(timeout: 10), "The main comic action must not enter the novel WebView")
        let image = app.images["comic.image.1"]
        XCTAssertTrue(image.waitForExistence(timeout: 8))
        capture("comic-strip-fit", app: app)
        let touch = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        touch.doubleTap()
        capture("comic-strip-native-zoom", app: app)
        touch.doubleTap()
        strip.swipeUp()
        strip.swipeUp()
        strip.swipeDown()
        capture("comic-strip-reversed", app: app)
        let mode = element("comic.readingMode", in: app)
        if !mode.isHittable { touch.tap() }
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.tap()
        app.buttons["左右翻页"].tap()
        XCTAssertTrue(element("comic.pageSurface", in: app).waitForExistence(timeout: 5))
        capture("comic-horizontal", app: app)
        mode.tap()
        app.buttons["日漫翻页"].tap()
        capture("comic-rtl", app: app)
        element("comic.return", in: app).tap()
        let decline = app.buttons["暂不加入"].firstMatch
        XCTAssertTrue(decline.waitForExistence(timeout: 5), "A successful comic preview must offer shelf membership too")
        decline.tap()
        XCTAssertTrue(read.isHittable, "Comic return must leave the owning detail route intact")
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
