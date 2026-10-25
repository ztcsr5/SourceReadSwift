import Foundation
import QuartzCore
import UIKit

/// 帧率采样累加器。
///
/// `#12` 的投诉是「滑动不够丝滑」，这跟「滚动回调耗时」不是一回事：
/// 回调只占一帧里的一小段，真正决定体感的是**每秒出了几帧、有多少帧超时**。
/// 这个累加器只做算术，便于在 CI 上锁住判定口径。
struct ReaderFrameRateAccumulator: Equatable {
    private(set) var frames: Int
    private(set) var droppedFrames: Int
    private(set) var totalSeconds: Double

    /// 超过期望帧间隔 2 倍才算掉一帧（60Hz 下约 33ms，即真正丢了 2 帧）。
    ///
    /// 原来用 1.5 倍：60Hz 下 25ms 就判掉帧，而 27fps 场景每帧约 37ms，
    /// 于是掉帧率虚高到 99%（诊断页实测 2508/2524），指标失去意义。
    static let dropThreshold: Double = 2.0

    init(frames: Int = 0, droppedFrames: Int = 0, totalSeconds: Double = 0) {
        self.frames = frames
        self.droppedFrames = droppedFrames
        self.totalSeconds = totalSeconds
    }

    /// - Parameters:
    ///   - delta: 相邻两帧的时间间隔（秒）。
    ///   - expectedFrameDuration: 该设备的期望帧间隔（1 / 刷新率）。
    mutating func recordFrame(delta: Double, expectedFrameDuration: Double) {
        guard delta.isFinite, delta > 0, expectedFrameDuration > 0 else { return }
        frames += 1
        totalSeconds += delta
        if delta > expectedFrameDuration * Self.dropThreshold {
            droppedFrames += 1
        }
    }

    var averageFPS: Double {
        totalSeconds > 0 ? Double(frames) / totalSeconds : 0
    }

    var droppedRatio: Double {
        frames > 0 ? Double(droppedFrames) / Double(frames) : 0
    }

    mutating func reset() {
        frames = 0
        droppedFrames = 0
        totalSeconds = 0
    }

    func merged(with other: ReaderFrameRateAccumulator) -> ReaderFrameRateAccumulator {
        ReaderFrameRateAccumulator(
            frames: frames + other.frames,
            droppedFrames: droppedFrames + other.droppedFrames,
            totalSeconds: totalSeconds + other.totalSeconds
        )
    }
}

/// 用 `CADisplayLink` 采样阅读器的实际出帧情况，结果落到 UserDefaults，
/// 于是用户在 设置 → 阅读器性能（诊断）里能直接读到，不用连 Xcode。
///
/// 只在有阅读器存活时运行；多个阅读器实例用引用计数管理同一个 link。
@MainActor
final class ReaderFrameRateSampler {
    static let shared = ReaderFrameRateSampler()

    private static let framesKey = "reader.frameRate.frames"
    private static let droppedKey = "reader.frameRate.dropped"
    private static let secondsKey = "reader.frameRate.seconds"
    private static let flushInterval = 600

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var expectedFrameDuration: Double = 1.0 / 60.0
    private var activeCount = 0
    private var pending = ReaderFrameRateAccumulator()

    private init() {}

    func begin() {
        activeCount += 1
        guard link == nil else { return }
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let maximum = scene?.screen.maximumFramesPerSecond ?? 60
        let ceiling = ReaderPerformancePolicy.preferredRefreshRate(maximumFramesPerSecond: maximum)
        expectedFrameDuration = 1.0 / Double(max(ceiling, 60))
        lastTimestamp = 0
        let link = CADisplayLink(target: self, selector: #selector(handleFrame(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func end() {
        activeCount = max(activeCount - 1, 0)
        guard activeCount == 0 else { return }
        link?.invalidate()
        link = nil
        lastTimestamp = 0
        flush()
    }

    static var snapshot: ReaderFrameRateAccumulator {
        let defaults = UserDefaults.standard
        let persisted = ReaderFrameRateAccumulator(
            frames: defaults.integer(forKey: framesKey),
            droppedFrames: defaults.integer(forKey: droppedKey),
            totalSeconds: defaults.double(forKey: secondsKey)
        )
        return persisted.merged(with: shared.pending)
    }

    static func reset() {
        shared.pending.reset()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: framesKey)
        defaults.removeObject(forKey: droppedKey)
        defaults.removeObject(forKey: secondsKey)
    }

    @objc private func handleFrame(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard lastTimestamp > 0 else { return }
        pending.recordFrame(delta: link.timestamp - lastTimestamp, expectedFrameDuration: expectedFrameDuration)
        if pending.frames >= Self.flushInterval {
            flush()
        }
    }

    private func flush() {
        guard pending.frames > 0 else { return }
        let defaults = UserDefaults.standard
        let combined = ReaderFrameRateAccumulator(
            frames: defaults.integer(forKey: Self.framesKey),
            droppedFrames: defaults.integer(forKey: Self.droppedKey),
            totalSeconds: defaults.double(forKey: Self.secondsKey)
        ).merged(with: pending)
        defaults.set(combined.frames, forKey: Self.framesKey)
        defaults.set(combined.droppedFrames, forKey: Self.droppedKey)
        defaults.set(combined.totalSeconds, forKey: Self.secondsKey)
        pending.reset()
    }
}
