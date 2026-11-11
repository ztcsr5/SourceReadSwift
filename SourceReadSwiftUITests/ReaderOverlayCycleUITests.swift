import XCTest

/// Exercises repeated native navigation using actual app controls and edge input.
final class ReaderOverlayCycleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--floating-desk-regression", "--desk-resume-paragraph", "--reader-edge-input-trace",
                               "-settings.visualTheme", "classic", "-settings.themeMode", "light",
                               "-settings.readingDeskEnabled", "YES",
                               "-reader.mode", "scroll", "-reader.textSelectionEnabled", "NO"]
        app.launch()
    }

    func testTwentyEnterExitCyclesKeepTheOverlayWorking() throws {
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bookshelf.continue."))
            .firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 20), "书架必须就绪")

        var missingNativeMotion: [Int] = []
        var missingSystemZoom: [Int] = []
        for cycle in 1...20 {
            entry.tap()

            let surface = app.webViews.firstMatch
            XCTAssertTrue(surface.waitForExistence(timeout: 25),
                          "第 \(cycle) 次进入必须在超时内出现正文")
            let evidence = app.otherElements["reader.navigationEvidence"]
            XCTAssertTrue(evidence.waitForExistence(timeout: 10))
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let value = evidence.value as? String ?? ""
                return value.contains("phase=reading") && value.contains("web=1;loads=1;presented=true")
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
            let saved = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "【已保存的阅读段落】")).firstMatch
            XCTAssertTrue(saved.exists && surface.frame.intersects(saved.frame), "Cycle \(cycle) must start at the saved paragraph")
            let identity = evidence.value as? String
            let motion = app.otherElements["reader.nativeBookGestureEvidence"]
            XCTAssertTrue(motion.waitForExistence(timeout: 5))
            let before = Int((motion.value as? String) ?? "") ?? (-1)
            XCTAssertGreaterThanOrEqual(before, 0)
            let zoomBefore = zoomBeginCount(in: evidence.label)
            let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.008, dy: 0.52))
            edge.press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.13, dy: 0.52)),
                withVelocity: .slow, thenHoldForDuration: 0.8)
            let cancelled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                (evidence.value as? String) == identity && surface.isHittable
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [cancelled], timeout: 5), .completed,
                           "Cancellation must preserve the session, WebView and shell navigation count")
            let after = Int((motion.value as? String) ?? "") ?? (-1)
            let zoomAfter = zoomBeginCount(in: evidence.label)
            let hasNativeMotion = after > before
            let hasExpectedZoom: Bool
            if #available(iOS 18.0, *) {
                hasExpectedZoom = zoomBefore >= 0 && zoomAfter > zoomBefore
            } else {
                hasExpectedZoom = true
            }
            let firstGestureFailure = missingNativeMotion.isEmpty && missingSystemZoom.isEmpty
            if !hasNativeMotion { missingNativeMotion.append(cycle) }
            if !hasExpectedZoom { missingSystemZoom.append(cycle) }
            if firstGestureFailure && (!hasNativeMotion || !hasExpectedZoom) {
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "reader-cycle-\(cycle)-missing-native-return"
                screenshot.lifetime = .keepAlways
                add(screenshot)
                print("BOOK_NATIVE_CYCLE \(cycle) \(evidence.label) \(motion.label)")
            }
            print("BOOK_NATIVE_CYCLE_RESULT \(cycle) motion=\(hasNativeMotion) zoom=\(hasExpectedZoom)")
            XCTAssertTrue(saved.exists && surface.frame.intersects(saved.frame), "Cycle \(cycle) must retain the saved paragraph")

            let back = app.buttons["reader.returnToShelf"]
            if !back.isHittable {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)).tap()
            }
            XCTAssertTrue(back.waitForExistence(timeout: 10), "第 \(cycle) 次必须能看到返回按钮")
            back.tap()

            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == NO"),
                                                 object: surface)
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 20), .completed,
                           "第 \(cycle) 次退出后覆盖层必须卸载")

            XCTAssertTrue(entry.waitForExistence(timeout: 10),
                          "第 \(cycle) 次退出后必须回到书架")
            XCTAssertTrue(entry.isHittable, "第 \(cycle) 次退出后书架必须可交互")
        }
        // A missed gesture leaves a usable reader, so collect the full series without retrying that drag.
        XCTAssertTrue(missingNativeMotion.isEmpty && missingSystemZoom.isEmpty,
                      "All 20 cycles must cancel real transitions; motion missing: \(missingNativeMotion); Zoom missing: \(missingSystemZoom)")
    }

    private func zoomBeginCount(in label: String) -> Int {
        let field = label.split(separator: ";").first { $0.hasPrefix("zoomBegins=") }
        return field.flatMap { Int($0.dropFirst("zoomBegins=".count)) } ?? -1
    }
}
