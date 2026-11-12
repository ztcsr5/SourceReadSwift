import XCTest

/// Copied into the UI test target only by the isolated experiment workflow.
/// Every condition uses one native stack and one unchanged touch sequence.
final class ReaderZoomExperimentUITests: XCTestCase {
    func testTwentyAttemptsForEachControlledPage() throws {
        continueAfterFailure = true
        // 80 recorded attempts cannot fit XCTest's 10-minute default. This is
        // a ceiling for the whole collection, not a per-round wait: every round
        // still settles on real evidence and all 80 are always recorded.
        // Four conditions × 20 rounds at ~11 s each needs headroom beyond the
        // original 25-minute ceiling; it is still a ceiling, not a per-round wait.
        executionTimeAllowance = 2_400
        let app = XCUIApplication()
        app.launchArguments = ["--floating-desk-regression", "--reader-zoom-isolation",
                               "-settings.themeMode", "light", "-reader.mode", "scroll"]
        app.launch()
        let selector = app.segmentedControls["experiment.condition"]
        guard selector.waitForExistence(timeout: 20) else {
            XCTFail("Independent experiment window did not mount; no gesture conclusions are valid")
            return
        }
        var rounds: [[String: Any]] = []
        var navigationIdentity: String?
        for condition in ["A", "D", "F", "G"] {
            for attempt in 1...20 {
                var failure: String?
                if selector.isHittable { selector.buttons[condition].tap() }
                let open = app.buttons["experiment.open"]
                if open.isHittable { open.tap() }
                let evidence = app.otherElements["experiment.evidence"].firstMatch
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    (self.read(evidence)["ready"] as? Bool) == true && app.buttons["experiment.arm"].isHittable
                }, object: nil)
                let prepared = XCTWaiter.wait(for: [ready], timeout: 15) == .completed
                if prepared {
                    app.buttons["experiment.arm"].tap()
                    let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.008, dy: 0.52))
                    edge.press(forDuration: 0.05,
                        thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.13, dy: 0.52)),
                        withVelocity: .slow, thenHoldForDuration: 0.8)
                    let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                        let outcome = (self.read(evidence)["outcome"] as? String) ?? "pending"
                        return outcome != "pending" && outcome != "notArmed"
                    }, object: nil)
                    if XCTWaiter.wait(for: [settled], timeout: 8) != .completed { failure = "settleTimeout" }
                } else {
                    failure = "pageNotReady-inputNotSent"
                }
                var report = read(evidence)
                report["attempt"] = attempt
                report["requestedCondition"] = condition
                report["inputSent"] = prepared
                #if targetEnvironment(simulator)
                report["environment"] = "simulator"
                #else
                report["environment"] = "physicalDevice"
                #endif
                report["input"] = ["startX": 0.008, "endX": 0.13, "y": 0.52,
                                   "pressSeconds": 0.05, "holdSeconds": 0.8, "speed": "slow"] as [String: Any]
                let identity = report["navigation"] as? String
                if navigationIdentity == nil { navigationIdentity = identity }
                if identity != navigationIdentity { failure = "navigationIdentityChanged" }
                if (report["condition"] as? String) != condition { failure = "wrongCondition" }
                if (report["truncated"] as? Bool) == true { failure = "truncatedEvidence" }
                // An unpositioned page cannot be used to judge edge arbitration:
                // the saved paragraph must be inside the viewport before input.
                let viewport = report["initialViewport"] as? [String: Any]
                if condition != "A", (viewport?["visible"] as? Bool) != true {
                    failure = failure ?? "openingPositionNotVisible"
                }
                let outcome = (report["outcome"] as? String) ?? "missing"
                if !["cancelled", "zoomMovedThenRestored"].contains(outcome) { failure = failure ?? outcome }
                if (report["expectedTouches"] as? Int) != 1 { failure = failure ?? "touchNotObservedOnPage" }
                report["failure"] = failure as Any? ?? NSNull()
                let attachment = XCTAttachment(string: encode(report))
                attachment.name = "zoom-\(condition)-\(String(format: "%02d", attempt))"
                attachment.lifetime = .keepAlways
                add(attachment)
                var summary = report
                summary.removeValue(forKey: "events")
                rounds.append(summary)
                print("ZOOM_EXPERIMENT condition=\(condition) attempt=\(attempt) outcome=\(outcome) failure=\(failure ?? "none")")
                let close = app.buttons["experiment.close"]
                if close.isHittable { close.tap() }
                let backAtRoot = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == YES"), object: open)
                _ = XCTWaiter.wait(for: [backAtRoot], timeout: 5)
            }
        }
        let report = XCTAttachment(string: encode(["rounds": rounds, "plannedAttemptsPerCondition": 20,
                                                     "conditions": ["A", "D", "F", "G"]]))
        report.name = "zoom-experiment-summary"
        report.lifetime = .keepAlways
        add(report)
        let failures = rounds.filter { $0["failure"] as? String != nil }
        XCTAssertEqual(rounds.count, 80)
        XCTAssertTrue(failures.isEmpty,
                      "Recorded all 80 attempts; \(failures.count) failed. Inspect per-round evidence before drawing a cause.")
    }

    private func read(_ evidence: XCUIElement) -> [String: Any] {
        guard evidence.exists, let text = evidence.value as? String, let bytes = text.data(using: .utf8),
              let report = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return [:] }
        return report
    }

    private func encode(_ report: [String: Any]) -> String {
        guard let bytes = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
              let text = String(data: bytes, encoding: .utf8) else { return "{\"encodingFailed\":true}" }
        return text
    }
}
