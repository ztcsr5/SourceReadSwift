import XCTest

/// 覆盖层进入/退出循环压测。
///
/// 目的：抓「第二次、第三次之后手势失效」这类识别器状态未复位的问题。
/// 只走真实 UI 路径（点正在阅读卡进入、点阅读器返回按钮退出），不注入模拟事件。
final class ReaderOverlayCycleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--floating-desk-regression", "--desk-resume-paragraph", "-settings.visualTheme", "classic",
                               "-settings.readingDeskEnabled", "YES",
                               "-reader.mode", "scroll"]
        app.launch()
    }

    func testTwentyEnterExitCyclesKeepTheOverlayWorking() throws {
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bookshelf.continue."))
            .firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 20), "书架必须就绪")

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
            let identity = evidence.value as? String
            let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.008, dy: 0.52))
            edge.press(forDuration: 0.2,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.13, dy: 0.52)),
                withVelocity: .slow, thenHoldForDuration: 0.8)
            let cancelled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                (evidence.value as? String) == identity && surface.isHittable
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [cancelled], timeout: 5), .completed,
                           "Cancellation must preserve the session, WebView and shell navigation count")

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
    }
}
