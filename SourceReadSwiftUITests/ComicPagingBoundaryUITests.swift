import XCTest

final class ComicPagingBoundaryUITests: XCTestCase {
    func testImportedCBZOpensTheNativeComicReaderAndReturnsToItsShelf() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--local-comic-regression", "-settings.reducesMotion", "YES"]
        app.launch()
        defer { capture("cbz-native-reader-final", app: app); app.terminate() }
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "bookshelf.continue.", "CBZ")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let strip = app.collectionViews["comic.stripSurface"]
        XCTAssertTrue(strip.waitForExistence(timeout: 10), "An imported CBZ must not enter the novel WebView")
        XCTAssertTrue(app.images["comic.image.1"].waitForExistence(timeout: 8))
        XCTAssertFalse(element("reader.webScrollSurface", in: app).exists)
        strip.swipeUp()
        XCTAssertTrue(app.images["comic.image.2"].waitForExistence(timeout: 8))
        let back = element("comic.return", in: app)
        if !back.isHittable { strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
        XCTAssertTrue(back.isHittable)
        capture("cbz-local-strip", app: app)
        back.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(entry.isHittable)
        XCTAssertFalse(app.alerts.firstMatch.exists, "A local import is already on the shelf")
    }

    func testPinchPansTheSameImageAndReleasesPagingAfterReturningToFit() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--comic-reader-regression", "-settings.reducesMotion", "YES"]
        app.launch()
        defer { capture("comic-pinch-final", app: app); app.terminate() }
        openComicPreview(in: app)
        let strip = app.collectionViews["comic.stripSurface"]
        XCTAssertTrue(strip.waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["comic.image.1"].waitForExistence(timeout: 8))
        let mode = element("comic.readingMode", in: app)
        if !mode.isHittable { strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
        mode.tap()
        app.buttons["左右翻页"].tap()
        let pager = element("comic.pageSurface", in: app)
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        assertComicPage(chapter: 1, page: 1, app: app)
        // XCTest's inward pinch starts near the surface edges. Hide the chrome
        // so both fingers land on the bitmap instead of the menu and slider.
        pager.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
            object: element("comic.readingMode", in: app))
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3), .completed)
        XCTAssertEqual(pager.value as? String, "第1话，第 1 页，共 6 页")
        let image = pager.images["漫画图片"].firstMatch
        pager.pinch(withScale: 2, velocity: 1)
        let zoomed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = image.value as? String, let percentage = Int(value.filter(\.isNumber)) else { return false }
            return percentage > 120
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [zoomed], timeout: 5), .completed)
        pager.swipeLeft()
        XCTAssertEqual(pager.value as? String, "第1话，第 1 页，共 6 页")
        XCTAssertTrue(image.frame.contains(CGPoint(x: pager.frame.midX, y: pager.frame.midY)))
        capture("comic-pinch-pan-same-page", app: app)
        pager.pinch(withScale: 0.4, velocity: -1)
        let fitted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            image.value as? String == "放大 100%"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [fitted], timeout: 5), .completed)
        pager.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        assertComicPage(chapter: 1, page: 1, app: app)
        pager.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        assertComicPage(chapter: 1, page: 2, app: app)
    }

    func testLeftToRightTapBoundariesRetainPageOrderAcrossBothChapters() {
        checkTapBoundaries(rtl: false)
    }

    func testRightToLeftTapBoundariesMirrorSidesWithoutReversingPageNumbers() {
        checkTapBoundaries(rtl: true)
    }

    private func checkTapBoundaries(rtl: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--comic-reader-regression", "-settings.reducesMotion", "YES"]
        app.launch()
        defer {
            capture(rtl ? "comic-rtl-boundaries-final" : "comic-ltr-boundaries-final", app: app)
            app.terminate()
        }
        openComicPreview(in: app)
        let strip = app.collectionViews["comic.stripSurface"]
        XCTAssertTrue(strip.waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["comic.image.1"].waitForExistence(timeout: 8))
        let mode = element("comic.readingMode", in: app)
        if !mode.isHittable {
            strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        }
        XCTAssertTrue(mode.isHittable)
        mode.tap()
        app.buttons[rtl ? "日漫翻页" : "左右翻页"].tap()
        let pager = element("comic.pageSurface", in: app)
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        let forward = pager.coordinate(withNormalizedOffset: CGVector(dx: rtl ? 0.15 : 0.85, dy: 0.5))
        let backward = pager.coordinate(withNormalizedOffset: CGVector(dx: rtl ? 0.85 : 0.15, dy: 0.5))
        assertComicPage(chapter: 1, page: 1, app: app)
        backward.tap()
        assertComicPage(chapter: 1, page: 1, app: app)
        for page in 2...6 {
            forward.tap()
            assertComicPage(chapter: 1, page: page, app: app)
        }
        forward.tap()
        assertComicPage(chapter: 2, page: 1, app: app)
        capture(rtl ? "comic-rtl-next-chapter" : "comic-ltr-next-chapter", app: app)
        backward.tap()
        assertComicPage(chapter: 1, page: 6, app: app)
        forward.tap()
        assertComicPage(chapter: 2, page: 1, app: app)
        for page in 2...6 {
            forward.tap()
            assertComicPage(chapter: 2, page: page, app: app)
        }
        forward.tap()
        assertComicPage(chapter: 2, page: 6, app: app)
        XCTAssertFalse(app.alerts.firstMatch.exists, "Reaching the last page must not exit or offer shelf membership")
    }

    private func assertComicPage(chapter: Int, page: Int, app: XCUIApplication) {
        let chapterLabel = app.staticTexts["comic.chapterTitle"]
        let pageLabel = app.staticTexts["comic.pageNumber"]
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard chapterLabel.label == "第\(chapter)话", pageLabel.label == String(page) else { return false }
            let pager = self.element("comic.pageSurface", in: app)
            return pager.images.matching(NSPredicate(format: "label == %@", "漫画图片")).allElementsBoundByIndex.contains {
                $0.frame.contains(CGPoint(x: pager.frame.midX, y: pager.frame.midY))
            }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landed], timeout: 6), .completed,
                       "The native paged reader must land on chapter \(chapter), page \(page)")
        XCTAssertTrue(element("comic.pageSurface", in: app).isHittable)
        XCTAssertFalse(app.collectionViews["comic.stripSurface"].exists)
    }

    private func openComicPreview(in app: XCUIApplication) {
        openComicDetails(in: app)
        let read = element("bookDetail.read", in: app)
        XCTAssertTrue(read.waitForExistence(timeout: 8)); read.tap()
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
