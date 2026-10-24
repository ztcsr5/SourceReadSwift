import Foundation

/// 滚动回调耗时累加器。
///
/// 纯值类型、无副作用，唯一职责是把「每帧花了多少毫秒」聚合成平均 / 最差 / 样本数，
/// 以便在 CI 上被测；真正采集留给 UIKit 的滚动回调。
struct ReaderScrollPerfAccumulator: Equatable {
    private(set) var frames: Int
    private(set) var totalMilliseconds: Double
    private(set) var worstMilliseconds: Double

    init(frames: Int = 0, totalMilliseconds: Double = 0, worstMilliseconds: Double = 0) {
        self.frames = frames
        self.totalMilliseconds = totalMilliseconds
        self.worstMilliseconds = worstMilliseconds
    }

    /// - Parameter cost: 单帧耗时，单位**秒**（与 `CACurrentMediaTime()` 差值一致）。
    mutating func record(cost: Double) {
        guard cost.isFinite, cost >= 0 else { return }
        frames += 1
        let milliseconds = cost * 1000
        totalMilliseconds += milliseconds
        worstMilliseconds = max(worstMilliseconds, milliseconds)
    }

    var averageMilliseconds: Double {
        frames > 0 ? totalMilliseconds / Double(frames) : 0
    }

    mutating func reset() {
        frames = 0
        totalMilliseconds = 0
        worstMilliseconds = 0
    }

    /// 合并两段采样（已落盘的历史 + 还没落盘的尾巴）。
    func merged(with other: ReaderScrollPerfAccumulator) -> ReaderScrollPerfAccumulator {
        ReaderScrollPerfAccumulator(
            frames: frames + other.frames,
            totalMilliseconds: totalMilliseconds + other.totalMilliseconds,
            worstMilliseconds: max(worstMilliseconds, other.worstMilliseconds)
        )
    }
}

/// 滚动性能采样：让用户**不连 Xcode**也能在设置里读到数字。
///
/// 线程约定：只在主线程使用（`scrollViewDidScroll` 与设置页都在主线程）。
/// 写盘节流到每 240 帧一次，避免每帧都打 UserDefaults。
enum ReaderScrollPerfMeter {
    private static let framesKey = "reader.scrollPerf.frames"
    private static let totalKey = "reader.scrollPerf.totalMs"
    private static let worstKey = "reader.scrollPerf.worstMs"
    private static let flushInterval = 240

    private static var pending = ReaderScrollPerfAccumulator()

    static func record(cost: Double) {
        pending.record(cost: cost)
        if pending.frames >= flushInterval {
            flush()
        }
    }

    /// 历史（已落盘）+ 本次未落盘的采样。
    static var snapshot: ReaderScrollPerfAccumulator {
        persisted.merged(with: pending)
    }

    static func reset() {
        pending.reset()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: framesKey)
        defaults.removeObject(forKey: totalKey)
        defaults.removeObject(forKey: worstKey)
    }

    private static var persisted: ReaderScrollPerfAccumulator {
        let defaults = UserDefaults.standard
        return ReaderScrollPerfAccumulator(
            frames: defaults.integer(forKey: framesKey),
            totalMilliseconds: defaults.double(forKey: totalKey),
            worstMilliseconds: defaults.double(forKey: worstKey)
        )
    }

    private static func flush() {
        guard pending.frames > 0 else { return }
        let combined = persisted.merged(with: pending)
        let defaults = UserDefaults.standard
        defaults.set(combined.frames, forKey: framesKey)
        defaults.set(combined.totalMilliseconds, forKey: totalKey)
        defaults.set(combined.worstMilliseconds, forKey: worstKey)
        pending.reset()
    }
}
