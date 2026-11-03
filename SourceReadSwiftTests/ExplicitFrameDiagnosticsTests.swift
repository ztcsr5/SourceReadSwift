import XCTest
import Combine
import UIKit
@testable import SourceReadSwift

@MainActor
final class ExplicitFrameDiagnosticsTests: XCTestCase {
    func testRepeatedStartStopOwnsOneBoundedSampler() {
        let profiler = AppFrameProfiler.shared
        profiler.stop()
        defer { profiler.stop() }
        XCTAssertFalse(profiler.hasActiveDisplayLink)
        XCTAssertFalse(ReaderScrollPerfMeter.isRecording)
        profiler.start()
        profiler.start()
        XCTAssertTrue(profiler.hasActiveDisplayLink)
        XCTAssertTrue(profiler.hasPendingDeadline)
        XCTAssertTrue(ReaderScrollPerfMeter.isRecording)
        profiler.stop()
        profiler.stop()
        XCTAssertFalse(profiler.hasActiveDisplayLink)
        XCTAssertFalse(profiler.hasPendingDeadline)
        XCTAssertFalse(ReaderScrollPerfMeter.isRecording)
        XCTAssertTrue(profiler.report.contains("不代表 GPU 实际呈现"))
        XCTAssertFalse(profiler.report.contains("fps"))
    }

    func testBackgroundStopsSamplingAndForegroundDoesNotRestartIt() async {
        let profiler = AppFrameProfiler.shared
        profiler.stop()
        defer { profiler.stop() }
        profiler.start()
        let stopped = expectation(description: "background stops diagnostics")
        let subscription = profiler.$isRecording.dropFirst().filter { !$0 }.prefix(1).sink { _ in stopped.fulfill() }
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        await fulfillment(of: [stopped], timeout: 2)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertFalse(profiler.isRecording)
        XCTAssertFalse(profiler.hasActiveDisplayLink)
        XCTAssertFalse(profiler.hasPendingDeadline)
        withExtendedLifetime(subscription) {}
    }

    func testDeadlineEndsExplicitSamplingWithoutAReaderReferenceCount() async {
        let profiler = AppFrameProfiler.shared
        profiler.stop()
        defer { profiler.stop() }
        profiler.start(duration: 0.02)
        let stopped = expectation(description: "finite diagnostic window")
        let subscription = profiler.$isRecording.dropFirst().filter { !$0 }.prefix(1).sink { _ in stopped.fulfill() }
        await fulfillment(of: [stopped], timeout: 2)
        XCTAssertFalse(profiler.hasActiveDisplayLink)
        XCTAssertFalse(profiler.hasPendingDeadline)
        withExtendedLifetime(subscription) {}
    }

    func testOrdinaryScrollDoesNotCollectDiagnosticSamples() {
        let wasRecording = ReaderScrollPerfMeter.isRecording
        ReaderScrollPerfMeter.isRecording = false
        defer { ReaderScrollPerfMeter.isRecording = wasRecording }
        let before = ReaderScrollPerfMeter.snapshot
        for _ in 0..<500 { ReaderScrollPerfMeter.record(cost: 0.001) }
        XCTAssertEqual(ReaderScrollPerfMeter.snapshot, before)
    }
}
