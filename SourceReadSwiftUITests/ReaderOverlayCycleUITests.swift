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
        // 20 real enter/exit cycles need ~620 s on CI; XCTest's default
        // 10-minute ceiling killed the runner after a fully green run and
        // reported it as "unexpected exit". This is a ceiling for the whole
        // collection, not a per-round wait: every round still settles on
        // real evidence and all 20 are always recorded.
        executionTimeAllowance = 1_500
        let firstEntry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bookshelf.continue."))
            .firstMatch
        XCTAssertTrue(firstEntry.waitForExistence(timeout: 20), "书架必须就绪")
        // 20 轮固定点同一本书：换书就是换封面源宿主，created 天然会变，
        // 那样测出来的是"书架轮换"而不是"返回时封面被销毁重建"。
        let bookID = String(firstEntry.identifier.dropFirst("bookshelf.continue.".count))
        XCTAssertFalse(bookID.isEmpty, "书桌卡片必须带书名 id")
        let entry = app.buttons["bookshelf.continue." + bookID]

        var missingNativeMotion: [Int] = []
        var missingSystemZoom: [Int] = []
        // 封面宿主身份：每轮读出全部 `<id>=created/alive`。同一个 id 的
        // created 只要在 20 轮里涨过，就说明源视图被真正销毁重建，返回时
        // 必然出现"空白后再加载"。alive==0 则是登记过的 view 已经死掉。
        // Distinct from `coverHostEntries(in:)`: a local of the same name
        // shadows the method and makes that call a "non-function" compile error.
        var coverHostsByCycle: [Int: [String: CoverHostState]] = [:]
        // 只对本次点击的那本书断言：书架上其它卡片随滚动被 SwiftUI 回收属正常，
        // 被点开的封面源才是"返回后空白再加载"的责任对象。
        var coverSourceByCycle: [Int: (id: String, state: CoverHostState)] = [:]
        var missingCoverSource: [String] = []
        // 生产默认必须是"子树依赖 + 关闭 highlight"。这里逐轮读实时自证，
        // 而不是从"手势成功"反推 gate 生效。
        var gateMismatches: [String] = []
        var lastGate = "unread"
        // 只要有一轮真的看到 WebKit 的 highlight 识别器，"全程 enabled=0" 就是
        // 证据；一轮都没看到说明探针没读到，不能算通过。
        var maxHighlightTotal = 0
        for cycle in 1...20 {
            XCTAssertTrue(entry.waitForExistence(timeout: 10),
                          "第 \(cycle) 次进入前必须还能看到这本书的卡片")
            entry.tap()

            let surface = app.webViews.firstMatch
            XCTAssertTrue(surface.waitForExistence(timeout: 25),
                          "第 \(cycle) 次进入必须在超时内出现正文")
            let evidence = app.otherElements["reader.navigationEvidence"]
            XCTAssertTrue(evidence.waitForExistence(timeout: 10))
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let value = (evidence.value as? String) ?? ""
                return value.contains("phase=reading") && value.contains("web=1;loads=1;presented=true")
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
            let saved = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "【已保存的阅读段落】")).firstMatch
            XCTAssertTrue(saved.exists && surface.frame.intersects(saved.frame), "Cycle \(cycle) must start at the saved paragraph")
            let identity = evidence.value as? String
            lastGate = waitForEdgeGate(in: evidence, timeout: 5)
            maxHighlightTotal = max(maxHighlightTotal, highlightCounts(lastGate).total)
            if let reason = edgeGateMismatch(lastGate) { gateMismatches.append("cycle \(cycle): \(reason) [\(lastGate)]") }
            let hosts = coverHostEntries(in: evidence.label)
            coverHostsByCycle[cycle] = hosts
            let sourceID = "continue|" + bookID
            if let source = hosts[sourceID] {
                coverSourceByCycle[cycle] = (sourceID, source)
            } else if hosts.isEmpty {
                missingCoverSource.append("cycle \(cycle): coverHosts 不可解析")
            } else {
                missingCoverSource.append("cycle \(cycle): 缺 \(sourceID)")
            }
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
            let cancelledOutcome = XCTWaiter.wait(for: [cancelled], timeout: 5)
            if cancelledOutcome != .completed {
                // Distinguish "the drag completed a real pop" from "the app
                // mutated its session during a cancelled drag": both fail the
                // same assertion but need opposite fixes.
                let current = (evidence.value as? String) ?? "nil"
                print("BOOK_NATIVE_CANCEL_DIVERGED cycle=\(cycle) same=\(current == identity) hittable=\(surface.isHittable) before=\(identity ?? "nil") after=\(current)")
            }
            XCTAssertEqual(cancelledOutcome, .completed,
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
        // created 是该 id 的跨轮累计值。20 轮固定点同一本书，正常情况下它
        // 全程恒为 1；一旦涨到 2，就是返回时源视图被销毁后重新登记了。
        let drifted = Set(coverSourceByCycle.values.map(\.state.created)).sorted()
        let deadTapped = coverSourceByCycle.filter { $0.value.state.alive < 1 }.keys.sorted()
        let hostsDump = coverHostsByCycle.sorted { $0.key < $1.key }
            .map { "cycle \($0.key): \($0.value)" }
            .joined(separator: " | ")
        print("BOOK_COVER_HOSTS \(hostsDump)")
        XCTAssertTrue(missingNativeMotion.isEmpty && missingSystemZoom.isEmpty,
                      "All 20 cycles must cancel real transitions; motion missing: \(missingNativeMotion); Zoom missing: \(missingSystemZoom)")
        // 20 次进出里同一本书的封面源宿主创建次数必须恒定。涨了就是源视图被
        // 销毁重建（返回后"空白再加载"的成因）；一次都没读到说明探针没挂上。
        XCTAssertEqual(coverSourceByCycle.count, 20,
                       "每轮都必须读到本次点击书籍的封面源：\(missingCoverSource)")
        XCTAssertEqual(Set(coverSourceByCycle.values.map(\.id)).count, 1,
                       "20 轮必须始终点同一本书，否则测的是换书不是重建")
        XCTAssertEqual(drifted, [1],
                       "封面源宿主全程只创建一次，实际 created 序列：\(drifted)")
        XCTAssertTrue(deadTapped.isEmpty, "被点开的书在这些轮次里封面源视图已失效：\(deadTapped)")
        print("BOOK_EDGE_GATE last=\(lastGate) maxHighlightTotal=\(maxHighlightTotal)")
        XCTAssertTrue(gateMismatches.isEmpty,
                      "生产默认必须让子树识别器等系统边缘手势、并关闭 highlight：\(gateMismatches)")
        XCTAssertGreaterThan(maxHighlightTotal, 0,
                             "20 轮里一次都没读到 WebKit highlight 识别器：gate 证据没有真正生效")
    }

    struct CoverHostState {
        let created: Int
        let alive: Int
    }

    /// Reads `coverHosts=<id>=created/alive,<id>=created/alive,...` from the
    /// reader evidence label. The payload is comma-joined and the very first
    /// `=` belongs to the `coverHosts=` key itself, so each entry has to be
    /// split at its own last `=`; reading the first `=` yields a book id and
    /// silently returns nil for every cycle.
    private func coverHostEntries(in label: String) -> [String: CoverHostState] {
        guard let field = label.split(separator: ";").first(where: { $0.hasPrefix("coverHosts=") })
        else { return [:] }
        var hosts: [String: CoverHostState] = [:]
        for raw in field.dropFirst("coverHosts=".count).split(separator: ",") {
            // Trailing fields of the same label fragment can follow a space.
            guard let token = raw.split(separator: " ").first,
                  let equals = token.lastIndex(of: "=") else { continue }
            let counts = token[token.index(after: equals)...].split(separator: "/")
            guard counts.count == 2,
                  let created = Int(counts[0].prefix(while: \.isNumber)),
                  let alive = Int(counts[1].prefix(while: \.isNumber)) else { continue }
            hosts[String(token[..<equals])] = CoverHostState(created: created, alive: alive)
        }
        return hosts
    }

    /// Reads `edgeGate=scope=<name> priority=<resolved|missing>
    /// highlight=<enabled>/<total> gated=...` from the same evidence label.
    /// The gate writes space-separated pairs because its `gated=` payload
    /// itself contains `;` and `,`; splitting the label on `;` would cut the
    /// first pair in half. `highlight` counts the recognizers the gate can see
    /// right now, so a gate that never ran reads `0/0` and cannot pass.
    private func edgeGateSummary(in label: String) -> String {
        guard let field = label.split(separator: ";").first(where: { $0.hasPrefix("edgeGate=") })
        else { return "edgeGate=missing" }
        return String(field.dropFirst("edgeGate=".count))
    }

    /// WebKit installs the highlight recognizer during its own layout, which can
    /// trail the first accessibility read. Poll the live state instead of
    /// sleeping; a gate that truly never reaches the recognizer stays `0/0`
    /// and still fails the caller's assertion.
    private func waitForEdgeGate(in evidence: XCUIElement, timeout: TimeInterval) -> String {
        // Wait until the recognizer set is visible, never for a good verdict:
        // a gate that truly missed the highlight stays 0/0 and still fails.
        let deadline = Date().addingTimeInterval(timeout)
        var summary = edgeGateSummary(in: evidence.label)
        while highlightCounts(summary).total == 0, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            summary = edgeGateSummary(in: evidence.label)
        }
        return summary
    }

    private func highlightCounts(_ summary: String) -> (enabled: Int, total: Int) {
        guard let field = summary.split(separator: " ").first(where: { $0.hasPrefix("highlight=") }) else { return (0, 0) }
        let counts = field.dropFirst("highlight=".count).split(separator: "/").compactMap { Int($0) }
        guard counts.count == 2 else { return (0, 0) }
        return (counts[0], counts[1])
    }

    /// Returns the reason this round is not proof, or nil when it is.
    private func edgeGateMismatch(_ summary: String) -> String? {
        guard summary.contains("scope=subtreeNoHighlight") else { return "scope" }
        guard summary.contains("priority=resolved") else { return "priority" }
        let counts = highlightCounts(summary)
        guard counts.total > 0 else { return "highlightSeen=0/0" }
        guard counts.enabled == 0 else { return "highlightEnabled=\(counts.enabled)/\(counts.total)" }
        return nil
    }

    private func zoomBeginCount(in label: String) -> Int {
        let field = label.split(separator: ";").first { $0.hasPrefix("zoomBegins=") }
        return field.flatMap { Int($0.dropFirst("zoomBegins=".count)) } ?? -1
    }
}
