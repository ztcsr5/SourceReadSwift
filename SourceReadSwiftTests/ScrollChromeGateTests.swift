import XCTest
@testable import SourceReadSwift

/// Batch A / item 5 — the navigation bar collapses on scroll. The gate is the
/// only part of that behaviour that can be asserted without a device: hysteresis,
/// upward reveal and the reset that a popped detail needs.
final class ScrollChromeGateTests: XCTestCase {
    func testBarCollapsesPastTheThresholdAndIgnoresSmallUpwardTravel() {
        let gate = ScrollChromeGate()
        var flips: [Bool] = []
        for offset in stride(from: CGFloat(0), through: -300, by: -20) {
            gate.update(offset: offset, now: 0) { flips.append($0) }
        }
        XCTAssertEqual(flips, [true], "Exactly one collapse, no oscillation at the boundary")
        XCTAssertTrue(gate.isCollapsed)

        gate.update(offset: -290, now: 0.5) { flips.append($0) }
        XCTAssertEqual(flips, [true], "Ten points back up is not a deliberate reveal")
        XCTAssertTrue(gate.isCollapsed)
    }

    func testUpwardTravelRevealsTheBar() {
        let gate = ScrollChromeGate()
        var flips: [Bool] = []
        gate.update(offset: -280, now: 0) { flips.append($0) }
        gate.update(offset: -290, now: 0.1) { flips.append($0) }
        gate.update(offset: -250, now: 0.3) { flips.append($0) }
        XCTAssertEqual(flips, [true, false])
        XCTAssertFalse(gate.isCollapsed)
    }

    func testReturningToTheTopAlwaysRevealsTheBar() {
        let gate = ScrollChromeGate()
        var flips: [Bool] = []
        gate.update(offset: -400, now: 0) { flips.append($0) }
        gate.update(offset: 0, now: 0.3) { flips.append($0) }
        XCTAssertEqual(flips, [true, false])
        XCTAssertFalse(gate.isCollapsed)
    }

    func testResetClearsHistorySoAPoppedDetailDoesNotInheritIt() {
        let gate = ScrollChromeGate()
        gate.update(offset: -400, now: 0) { _ in }
        XCTAssertTrue(gate.isCollapsed)

        gate.reset()
        XCTAssertFalse(gate.isCollapsed)

        var flips: [Bool] = []
        gate.update(offset: -260, now: 0) { flips.append($0) }
        XCTAssertEqual(flips, [true], "The gate must still collapse from a clean history")
    }

    func testSafeAreaJumpAfterCollapseDoesNotFlipTheBarBack() {
        let gate = ScrollChromeGate()
        var flips: [Bool] = []
        gate.update(offset: -300, now: 0) { flips.append($0) }
        // Hiding the navigation bar shrinks the top inset; the content offset
        // jumps down by the bar height on the next geometry callback.
        gate.update(offset: -240, now: 0.05) { flips.append($0) }
        gate.update(offset: -240, now: 0.4) { flips.append($0) }
        XCTAssertEqual(flips, [true], "The safe-area jump must not reveal the bar")
        XCTAssertTrue(gate.isCollapsed)
    }

    func testRealUpwardSwipeAfterTheSettleWindowStillReveals() {
        let gate = ScrollChromeGate()
        var flips: [Bool] = []
        gate.update(offset: -300, now: 0) { flips.append($0) }
        gate.update(offset: -240, now: 0.4) { flips.append($0) }
        gate.update(offset: -200, now: 0.5) { flips.append($0) }
        XCTAssertEqual(flips, [true, false])
    }

    func testShortShelfNeverCollapses() {
        let gate = ScrollChromeGate()
        var flips: [Bool] = []
        for offset in stride(from: CGFloat(0), through: -200, by: -10) {
            gate.update(offset: offset, now: 0) { flips.append($0) }
        }
        XCTAssertTrue(flips.isEmpty)
        XCTAssertFalse(gate.isCollapsed)
    }
}
