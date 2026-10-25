import XCTest
@testable import SourceReadSwift

/// 帧率口径必须稳定，否则「掉帧率 3%」这种数字没法当决策依据。
final class ReaderFrameRateSamplerTests: XCTestCase {

    private let fps60 = 1.0 / 60.0

    func testEmptyAccumulator() {
        let accumulator = ReaderFrameRateAccumulator()
        XCTAssertEqual(accumulator.frames, 0)
        XCTAssertEqual(accumulator.averageFPS, 0)
        XCTAssertEqual(accumulator.droppedRatio, 0)
    }

    func testSteadySixtyFPS() {
        var accumulator = ReaderFrameRateAccumulator()
        for _ in 0..<60 {
            accumulator.recordFrame(delta: fps60, expectedFrameDuration: fps60)
        }
        XCTAssertEqual(accumulator.frames, 60)
        XCTAssertEqual(accumulator.averageFPS, 60, accuracy: 0.5)
        XCTAssertEqual(accumulator.droppedFrames, 0)
    }

    func testFrameBeyondThresholdCountsAsDropped() {
        var accumulator = ReaderFrameRateAccumulator()
        accumulator.recordFrame(delta: fps60, expectedFrameDuration: fps60)
        accumulator.recordFrame(delta: fps60 * 2.5, expectedFrameDuration: fps60)
        XCTAssertEqual(accumulator.droppedFrames, 1)
        XCTAssertEqual(accumulator.droppedRatio, 0.5, accuracy: 0.0001)
    }

    func testFrameExactlyAtThresholdIsNotDropped() {
        var accumulator = ReaderFrameRateAccumulator()
        // dropThreshold 是严格的 >，正好 1.5 倍不算掉帧。
        accumulator.recordFrame(delta: fps60 * ReaderFrameRateAccumulator.dropThreshold, expectedFrameDuration: fps60)
        XCTAssertEqual(accumulator.droppedFrames, 0)
    }

    func testInvalidSamplesAreIgnored() {
        var accumulator = ReaderFrameRateAccumulator()
        accumulator.recordFrame(delta: 0, expectedFrameDuration: fps60)
        accumulator.recordFrame(delta: -0.01, expectedFrameDuration: fps60)
        accumulator.recordFrame(delta: .nan, expectedFrameDuration: fps60)
        accumulator.recordFrame(delta: fps60, expectedFrameDuration: 0)
        XCTAssertEqual(accumulator.frames, 0)
    }

    func testMergeCombinesFramesAndDrops() {
        var first = ReaderFrameRateAccumulator()
        first.recordFrame(delta: fps60, expectedFrameDuration: fps60)
        first.recordFrame(delta: fps60 * 3, expectedFrameDuration: fps60)

        var second = ReaderFrameRateAccumulator()
        second.recordFrame(delta: fps60, expectedFrameDuration: fps60)

        let merged = first.merged(with: second)
        XCTAssertEqual(merged.frames, 3)
        XCTAssertEqual(merged.droppedFrames, 1)
        XCTAssertEqual(merged.totalSeconds, fps60 + fps60 * 3 + fps60, accuracy: 0.0001)
    }

    func testReset() {
        var accumulator = ReaderFrameRateAccumulator()
        accumulator.recordFrame(delta: fps60, expectedFrameDuration: fps60)
        accumulator.reset()
        XCTAssertEqual(accumulator, ReaderFrameRateAccumulator())
    }
}
