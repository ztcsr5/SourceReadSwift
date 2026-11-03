import Foundation

/// Legacy callback accumulator retained for historical diagnostic compatibility.
/// Its threshold counts long callbacks, not the number of frames presented or dropped.
struct ReaderFrameRateAccumulator: Equatable {
    private(set) var frames: Int
    private(set) var droppedFrames: Int
    private(set) var totalSeconds: Double

    /// Historical threshold; not a render-deadline or dropped-frame metric.
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
        guard delta.isFinite, delta > 0, delta <= 0.5, expectedFrameDuration > 0 else { return }
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

/// Read-only compatibility for old diagnostic records. Normal reading never starts a sampler.
/// These counters describe historical main-run-loop callbacks, not presented frames.
@MainActor
enum ReaderFrameRateSampler {
    private static let framesKey = "reader.frameRate.frames"
    private static let droppedKey = "reader.frameRate.dropped"
    private static let secondsKey = "reader.frameRate.seconds"

    static var snapshot: ReaderFrameRateAccumulator {
        let defaults = UserDefaults.standard
        return ReaderFrameRateAccumulator(
            frames: defaults.integer(forKey: framesKey),
            droppedFrames: defaults.integer(forKey: droppedKey),
            totalSeconds: defaults.double(forKey: secondsKey)
        )
    }

    static func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: framesKey)
        defaults.removeObject(forKey: droppedKey)
        defaults.removeObject(forKey: secondsKey)
    }
}
