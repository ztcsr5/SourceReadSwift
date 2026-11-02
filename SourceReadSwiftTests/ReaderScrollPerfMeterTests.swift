import XCTest
@testable import SourceReadSwift

/// 滚动耗时聚合的纯逻辑。数字要能被人读懂，先得保证算法本身对。
final class ReaderScrollPerfMeterTests: XCTestCase {

    @MainActor func testScrollSamplesStayInMemoryUntilTheSessionFlushes() {
        let defaults = UserDefaults.standard
        let keys = ["reader.scrollPerf.frames", "reader.scrollPerf.totalMs", "reader.scrollPerf.worstMs"]
        ReaderScrollPerfMeter.flush()
        let original = keys.map { defaults.object(forKey: $0) }
        defer {
            ReaderScrollPerfMeter.reset()
            for (key, value) in zip(keys, original) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        ReaderScrollPerfMeter.reset()
        for _ in 0..<600 { ReaderScrollPerfMeter.record(cost: 0.001) }
        for key in keys { XCTAssertNil(defaults.object(forKey: key), "Scrolling must not periodically write defaults") }
        XCTAssertEqual(ReaderScrollPerfMeter.snapshot.frames, 600)
        ReaderScrollPerfMeter.flush()
        XCTAssertEqual(defaults.integer(forKey: keys[0]), 600)
        XCTAssertEqual(ReaderScrollPerfMeter.snapshot.frames, 600)
        ReaderScrollPerfMeter.flush()
        XCTAssertEqual(defaults.integer(forKey: keys[0]), 600, "Flushing twice cannot double-count samples")
    }

    func testEmptyAccumulatorHasZeroAverage() {
        let accumulator = ReaderScrollPerfAccumulator()
        XCTAssertEqual(accumulator.frames, 0)
        XCTAssertEqual(accumulator.averageMilliseconds, 0)
        XCTAssertEqual(accumulator.worstMilliseconds, 0)
    }

    func testRecordConvertsSecondsToMilliseconds() {
        var accumulator = ReaderScrollPerfAccumulator()
        accumulator.record(cost: 0.002)   // 2ms
        accumulator.record(cost: 0.004)   // 4ms
        XCTAssertEqual(accumulator.frames, 2)
        XCTAssertEqual(accumulator.averageMilliseconds, 3, accuracy: 0.0001)
        XCTAssertEqual(accumulator.worstMilliseconds, 4, accuracy: 0.0001)
    }

    func testWorstOnlyGrows() {
        var accumulator = ReaderScrollPerfAccumulator()
        accumulator.record(cost: 0.010)
        accumulator.record(cost: 0.001)
        XCTAssertEqual(accumulator.worstMilliseconds, 10, accuracy: 0.0001)
        XCTAssertEqual(accumulator.frames, 2)
    }

    func testInvalidSamplesAreIgnored() {
        var accumulator = ReaderScrollPerfAccumulator()
        accumulator.record(cost: -1)
        accumulator.record(cost: .nan)
        accumulator.record(cost: .infinity)
        XCTAssertEqual(accumulator.frames, 0)
    }

    func testMergeKeepsTotalAndWorst() {
        var first = ReaderScrollPerfAccumulator()
        first.record(cost: 0.004)
        first.record(cost: 0.006)

        var second = ReaderScrollPerfAccumulator()
        second.record(cost: 0.020)

        let merged = first.merged(with: second)
        XCTAssertEqual(merged.frames, 3)
        XCTAssertEqual(merged.totalMilliseconds, 30, accuracy: 0.0001)
        XCTAssertEqual(merged.worstMilliseconds, 20, accuracy: 0.0001)
        XCTAssertEqual(merged.averageMilliseconds, 10, accuracy: 0.0001)
    }

    func testMergeWithEmptyIsIdentity() {
        var accumulator = ReaderScrollPerfAccumulator()
        accumulator.record(cost: 0.003)
        let merged = accumulator.merged(with: ReaderScrollPerfAccumulator())
        XCTAssertEqual(merged, accumulator)
    }

    func testResetClearsEverything() {
        var accumulator = ReaderScrollPerfAccumulator()
        accumulator.record(cost: 0.005)
        accumulator.reset()
        XCTAssertEqual(accumulator, ReaderScrollPerfAccumulator())
    }
}
