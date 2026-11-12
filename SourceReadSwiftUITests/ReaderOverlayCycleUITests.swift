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
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bookshelf.continue."))
            .firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 20), "书架必须就绪")

        var missingNativeMotion: [Int] = []
        var missingSystemZoom: [Int] = []
        // 封面宿主身份：`created/alive`。每次退出再进入若都 +1，说明源视图
        // 被真正销毁重建，返回时必然出现"空白后再加载"。
        // Distinct from `coverHostCreations(in:)`: a local of the same name
        // shadows the method and makes that call a "non-function" compile error.
        var coverHostsByCycle: [Int: (created: Int, alive: Int)] = [:]
        // 生产默认必须是"子树依赖 + 关闭 highlight"。这里逐轮读实时自证，
        // 而不是从"手势成功"反推 gate 生效。
        var gateMismatches: [String] = []
        var lastGate = "unread"
        // 只要有一轮真的看到 WebKit 的 highlight 识别器，"全程 enabled=0" 就是
        // 证据；一轮都没看到说明探针没读到，不能算通过。
        var maxHighlightTotal = 0
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
            lastGate = waitForEdgeGate(in: evidence, timeout: 5)
            maxHighlightTotal = max(maxHighlightTotal, highlightCounts(lastGate).total)
            if let reason = edgeGateMismatch(lastGate) { gateMismatches.append("cycle \(cycle): \(reason) [\(lastGate)]") }
            if let hosts = coverHostCreations(in: evidence.label) { coverHostsByCycle[cycle] = hosts }
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
        let created = Set(coverHostsByCycle.values.map(\.created))
        let aliveLost = coverHostsByCycle.filter { $0.value.alive == 0 }.keys.sorted()
        print("BOOK_COVER_HOSTS \(coverHostsByCycle.sorted { $0.key < $1.key })")
        XCTAssertTrue(missingNativeMotion.isEmpty && missingSystemZoom.isEmpty,
                      "All 20 cycles must cancel real transitions; motion missing: \(missingNativeMotion); Zoom missing: \(missingSystemZoom)")
        // 20 次进出里同一个封面 id 的宿主创建次数必须恒定。涨了就是源视图被
        // 销毁重建（返回后"空白再加载"的成因）；一次都没读到说明探针没挂上。
        XCTAssertEqual(created.count, 1, "封面源宿主必须全程只创建一次：\(coverHostsByCycle)")
        XCTAssertNotEqual(created.first ?? 0, 0, "封面源宿主必须已登记：\(coverHostsByCycle)")
        XCTAssertTrue(aliveLost.isEmpty, "这些轮次读到的封面宿主已失效：\(aliveLost)")
        print("BOOK_EDGE_GATE last=\(lastGate) maxHighlightTotal=\(maxHighlightTotal)")
        XCTAssertTrue(gateMismatches.isEmpty,
                      "生产默认必须让子树识别器等系统边缘手势、并关闭 highlight：\(gateMismatches)")
        XCTAssertGreaterThan(maxHighlightTotal, 0,
                             "20 轮里一次都没读到 WebKit highlight 识别器：gate 证据没有真正生效")
    }

    /// Reads `coverHosts=<id>=created/alive` from the reader evidence label.
    /// Both halves matter: `created` growing means the SwiftUI cover host was
    /// thrown away and rebuilt; `alive == 0` means the registered view died.
    private func coverHostCreations(in label: String) -> (created: Int, alive: Int)? {
        guard let field = label.split(separator: ";").first(where: { $0.hasPrefix("coverHosts=") }),
              let equals = field.firstIndex(of: "="),
              let slash = field[equals...].firstIndex(of: "/"),
              let created = Int(field[field.index(after: equals)..<slash]),
              let alive = Int(field[field.index(after: slash)...].prefix(while: \.isNumber)) else { return nil }
        return (created, alive)
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
