import XCTest
import Combine
@testable import SourceReadSwift

final class AppFrameProfilerTests: XCTestCase {
    func test120CadenceAndSystem60CadenceAreNotConflated() {
        var h = AppFrameHistogram()
        for _ in 0..<120 { h.record(seconds: 1 / 120.0, scheduledSeconds: 1 / 120.0) }
        XCTAssertEqual(h.averageFPS, 120, accuracy: 0.01)
        XCTAssertEqual(h.over120Budget, 0)
        XCTAssertEqual(h.missedScheduledFrames, 0)
        h.record(seconds: 1 / 60.0, scheduledSeconds: 1 / 60.0)
        XCTAssertEqual(h.over120Budget, 1)
        XCTAssertEqual(h.missedScheduledFrames, 0, "Adaptive 60Hz is not a missed system deadline")
    }

    func testLongStallPercentilesAreNotClampedToHalfASecond() {
        var h = AppFrameHistogram()
        h.record(seconds: 1.25, scheduledSeconds: 1 / 120.0)
        XCTAssertEqual(h.percentileMilliseconds(0.99), 1250)
        XCTAssertEqual(h.missedScheduledFrames, 149)
        XCTAssertEqual(h.worstSeconds, 1.25)
    }

    func testInvalidIntervalsAreDiscarded() {
        var h = AppFrameHistogram()
        for v in [Double.nan, .infinity, -1, 0, 6] { h.record(seconds: v, scheduledSeconds: 1 / 120.0) }
        h.record(seconds: 1, scheduledSeconds: 0)
        XCTAssertEqual(h.samples, 0)
        XCTAssertEqual(h.percentileMilliseconds(.nan), 0)
        XCTAssertEqual(h.averageFPS, 0)
    }

    @MainActor func testDiagnosticAndSearchProgressDoNotInvalidateWholeApp() {
        let app = AppState()
        var notifications = 0
        let subscription = app.objectWillChange.sink { notifications += 1 }
        for i in 0..<250 { app.record(DiagnosticEvent(level: .info, stage: "fixture", message: "\(i)")) }
        app.discoverViewModel.objectWillChange.send()
        XCTAssertEqual(notifications, 0)
        XCTAssertEqual(app.diagnostics.count, 200)
        app.isTabChromeHidden.toggle()
        XCTAssertEqual(notifications, 1, "Real navigation state must still publish")
        withExtendedLifetime(subscription) {}
    }
}
