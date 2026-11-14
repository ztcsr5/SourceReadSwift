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
        let boundary = app.buttons["comic.chapterBoundary"]
        for _ in 0..<10 {
            if boundary.isHittable { break }
            strip.swipeUp()
        }
        XCTAssertTrue(boundary.isHittable)
        boundary.tap()
        let mode = element("comic.readingMode", in: app)
        if !mode.isHittable { touch.tap() }
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        let readerChapter = app.staticTexts["comic.chapterTitle"]
        let arrived = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            readerChapter.exists && readerChapter.label == "第2话"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [arrived], timeout: 5), .completed,
                      "The native strip boundary must enter the next chapter")
        capture("comic-next-chapter", app: app)
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

    func testComicReadingLineSurvivesBackgroundExitAndProcessRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--comic-reader-regression", "--comic-reader-session", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        openComicPreview(in: app)
        let strip = app.collectionViews["comic.stripSurface"]
        XCTAssertTrue(strip.waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["comic.image.1"].waitForExistence(timeout: 8))
        strip.swipeUp()
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let line = self.readingLine(strip) else { return false }
            return line.percent > 5 && line.percent < 95
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        let saved = try XCTUnwrap(readingLine(strip))
        capture("comic-before-background", app: app)
        XCUIDevice.shared.press(.home)
        app.activate()
        let touch = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let back = element("comic.return", in: app)
        if !back.isHittable { touch.tap() }
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        let add = app.alerts.buttons["加入书架"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let membership = element("bookDetail.shelfAction", in: app)
        let durable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            membership.value as? String == "已保存"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [durable], timeout: 5), .completed,
                       "Terminate only after the add action has acknowledged its real ordered disk writes")
        app.terminate()
        app.launch()
        let legacy = app.buttons["tabs.legacy.discover"]
        let discover = legacy.exists ? legacy : app.tabBars.buttons["寻书"]
        XCTAssertTrue(discover.waitForExistence(timeout: 5))
        discover.tap()
        let search = app.textFields["搜索书名或作者"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Comic\n")
        let result = app.staticTexts["Comic · 图片阅读样本"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10)); result.tap()
        let read = element("bookDetail.read", in: app)
        XCTAssertTrue(read.waitForExistence(timeout: 8)); read.tap()
        let resumed = app.collectionViews["comic.stripSurface"]
        XCTAssertTrue(resumed.waitForExistence(timeout: 10))
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let line = self.readingLine(resumed) else { return false }
            return line.page == saved.page && abs(line.percent - saved.percent) <= 3
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed,
                       "The real image layout must restore the saved line, not merely the page number")
        capture("comic-after-relaunch", app: app)
    }

    private func openComicPreview(in app: XCUIApplication) {
        openComicDetails(in: app)
        let read = element("bookDetail.read", in: app)
        XCTAssertTrue(read.waitForExistence(timeout: 8)); read.tap()
    }

    func testWholeComicDownloadReopensAfterOrdinaryCacheClearAndSourceFailure() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let launch = ["--comic-reader-regression", "--comic-reader-session", UUID().uuidString]
        app.launchArguments = launch
        app.launch()
        defer { app.terminate() }
        openComicDetails(in: app)
        let download = element("bookDetail.downloadComic", in: app)
        let detail = element("bookDetail.scroll", in: app)
        for _ in 0..<4 where !download.isHittable { detail.swipeUp() }
        XCTAssertTrue(download.isHittable)
        XCTAssertEqual(download.label, "下载全本漫画")
        download.tap()
        let complete = app.staticTexts["下载进度 2/2 话"]
        XCTAssertTrue(complete.waitForExistence(timeout: 20), "Both image archives must commit before the download reports complete")
        capture("comic-whole-book-downloaded", app: app)

        app.terminate()
        app.launchArguments = launch + ["--comic-reader-source-unavailable"]
        app.launch()
        let legacy = app.buttons["tabs.legacy.settings"]
        let settings = legacy.exists ? legacy : app.tabBars.buttons["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5)); settings.tap()
        let clear = element("settings.clearChapterCache", in: app)
        for _ in 0..<7 where !clear.isHittable { app.swipeUp() }
        XCTAssertTrue(clear.isHittable); clear.tap()
        let confirm = app.buttons["清除章节缓存"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        let offline = element("settings.offlineComics", in: app)
        let navBar = app.navigationBars.firstMatch
        let navBottom = navBar.exists ? navBar.frame.maxY : 120
        for _ in 0..<4 where !offline.exists || offline.frame.minY < navBottom + 4 {
            app.swipeDown()
        }
        for _ in 0..<4 where !offline.isHittable || offline.frame.maxY > app.frame.height - 88 {
            app.swipeUp()
        }
        XCTAssertTrue(offline.isHittable); offline.tap()
        let secondChapter = element("comic.offlineChapter.1", in: app)
        XCTAssertTrue(secondChapter.waitForExistence(timeout: 10)); secondChapter.tap()
        let strip = app.collectionViews["comic.stripSurface"]
        XCTAssertTrue(strip.waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["comic.image.1"].waitForExistence(timeout: 10),
                      "A decoded archive image, not just a cached URL, must reopen without its source")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.readingLine(strip)?.page == 1 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 6), .completed)
        capture("comic-offline-chapter-two-after-cache-clear", app: app)
    }

    private func openComicDetails(in app: XCUIApplication) {
        let legacy = app.buttons["tabs.legacy.discover"]
        let discover = legacy.exists ? legacy : app.tabBars.buttons["寻书"]
        XCTAssertTrue(discover.waitForExistence(timeout: 5)); discover.tap()
        let search = app.textFields["搜索书名或作者"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Comic\n")
        let result = app.staticTexts["Comic · 图片阅读样本"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10)); result.tap()
        XCTAssertTrue(element("bookDetail.read", in: app).waitForExistence(timeout: 8))
    }

    private func readingLine(_ strip: XCUIElement) -> (page: Int, percent: Int)? {
        guard let value = strip.value as? String else { return nil }
        let numbers = value.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
        guard numbers.count == 2 else { return nil }
        return (numbers[0], numbers[1])
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
