import Foundation
import XCTest
@testable import SourceReadSwift

@MainActor
final class SourceBatchCheckCoordinatorTests: XCTestCase {
    func testCoordinatorInitialStateAndCalculations() {
        let coordinator = SourceBatchCheckCoordinator()
        XCTAssertFalse(coordinator.isRunning)
        XCTAssertEqual(coordinator.progressFraction, 0.0)
        XCTAssertEqual(coordinator.checkedCount, 0)
        XCTAssertEqual(coordinator.totalCount, 0)
    }

    func testSourceBatchCheckStatusPriorityOrdering() {
        let failed = SourceBatchCheckStatus.failed
        let warning = SourceBatchCheckStatus.warning
        let passed = SourceBatchCheckStatus.passed

        XCTAssertTrue(failed.priority < warning.priority)
        XCTAssertTrue(warning.priority < passed.priority)
    }

    func testResultSortOrderErrorsFirstThenLatency() {
        var results = [
            SourceBatchCheckResult(sourceName: "A", sourceURL: "http://a", status: .passed, message: "OK", elapsedMilliseconds: 100),
            SourceBatchCheckResult(sourceName: "B", sourceURL: "http://b", status: .failed, message: "Fail", elapsedMilliseconds: 50),
            SourceBatchCheckResult(sourceName: "C", sourceURL: "http://c", status: .warning, message: "Warn", elapsedMilliseconds: 200),
            SourceBatchCheckResult(sourceName: "D", sourceURL: "http://d", status: .failed, message: "Fail 2", elapsedMilliseconds: 300)
        ]

        results.sort { lhs, rhs in
            if lhs.status.priority != rhs.status.priority {
                return lhs.status.priority < rhs.status.priority
            }
            if lhs.elapsedMilliseconds != rhs.elapsedMilliseconds {
                return lhs.elapsedMilliseconds > rhs.elapsedMilliseconds
            }
            return lhs.sourceName.localizedCaseInsensitiveCompare(rhs.sourceName) == .orderedAscending
        }

        XCTAssertEqual(results[0].sourceName, "D") // failed, 300ms
        XCTAssertEqual(results[1].sourceName, "B") // failed, 50ms
        XCTAssertEqual(results[2].sourceName, "C") // warning, 200ms
        XCTAssertEqual(results[3].sourceName, "A") // passed, 100ms
    }

    func testCoordinatorStopClearsStateGracefully() {
        let coordinator = SourceBatchCheckCoordinator()
        coordinator.stop()
        XCTAssertFalse(coordinator.isRunning)
    }
}
