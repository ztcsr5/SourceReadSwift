import Foundation
import Combine
import QuartzCore
import UIKit

/// Fixed-size histogram: no sort/allocation/SwiftUI publication per frame.
/// This measures main-run-loop display-link cadence, NOT GPU presentation.
struct AppFrameHistogram: Equatable {
    private(set) var buckets = [Int](repeating: 0, count: 5001)
    private(set) var samples = 0
    private(set) var totalSeconds = 0.0
    private(set) var worstSeconds = 0.0
    private(set) var over120Budget = 0
    private(set) var missedScheduledFrames = 0

    mutating func record(seconds: Double, scheduledSeconds: Double) {
        guard seconds.isFinite, scheduledSeconds.isFinite, seconds > 0,
              seconds <= 5, scheduledSeconds >= 0.001 else { return }
        samples += 1
        totalSeconds += seconds
        worstSeconds = max(worstSeconds, seconds)
        buckets[min(Int((seconds * 1000).rounded(.up)), 5000)] += 1
        if seconds > 1.0 / 120.0 + 0.0005 { over120Budget += 1 }
        missedScheduledFrames += max(Int((seconds / scheduledSeconds).rounded()) - 1, 0)
    }

    func percentileMilliseconds(_ percentile: Double) -> Double {
        guard samples > 0, percentile.isFinite else { return 0 }
        let rank = max(Int((Double(samples) * min(max(percentile, 0), 1)).rounded(.up)), 1)
        var cumulative = 0
        for (milliseconds, count) in buckets.enumerated() {
            cumulative += count
            if cumulative >= rank { return Double(milliseconds) }
        }
        return worstSeconds * 1000
    }

    var averageFPS: Double { totalSeconds > 0 ? Double(samples) / totalSeconds : 0 }
}

/// Opt-in, bounded sampling across ALL app screens. No always-on high-refresh
/// timer or per-frame UserDefaults writes; the result publishes only on stop.
@MainActor
final class AppFrameProfiler: ObservableObject {
    static let shared = AppFrameProfiler()
    @Published private(set) var isRecording = false
    @Published private(set) var report = "暂无全局采样。开始后切换到需要测试的页面操作 30 秒。"
    private var link: CADisplayLink?
    private var histogram = AppFrameHistogram()
    private var previous: CFTimeInterval = 0
    private var deadline: CFTimeInterval = 0
    private var maximum = 60
    private var startingPower = false
    private var startingThermal = 0
    private var observer: NSObjectProtocol?
    private var deadlineTask: Task<Void, Never>?
    var hasActiveDisplayLink: Bool { link != nil }
    var hasPendingDeadline: Bool { deadlineTask != nil }

    private init() {
        observer = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
                                                         object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    func start(duration: TimeInterval = 30) {
        guard !isRecording else { return }
        histogram = AppFrameHistogram()
        previous = 0
        maximum = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?.screen.maximumFramesPerSecond ?? 60
        startingPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        startingThermal = ProcessInfo.processInfo.thermalState.rawValue
        let duration = duration.isFinite ? min(max(duration, 0.01), 30) : 30
        deadline = CACurrentMediaTime() + duration
        let displayLink = CADisplayLink(target: self, selector: #selector(frame(_:)))
        // Observe the default callback cadence; do not request an 80–120 Hz floor
        // just by opening diagnostics. This still isn't GPU presentation timing.
        displayLink.add(to: .main, forMode: .common)
        link = displayLink
        isRecording = true
        ReaderScrollPerfMeter.reset()
        ReaderScrollPerfMeter.isRecording = true
        deadlineTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        guard isRecording else { return }
        deadlineTask?.cancel()
        deadlineTask = nil
        if let displayLink = link { displayLink.invalidate() }
        link = nil
        previous = 0
        ReaderScrollPerfMeter.isRecording = false
        ReaderScrollPerfMeter.flush()
        isRecording = false
        let h = histogram
        report = String(format: "屏幕能力：%d Hz\n采样：%d 次回调 / %.2f 秒\n平均回调频率：%.1f 次/秒\n回调间隔 P95 / P99：%.0f / %.0f ms\n最慢间隔：%.2f ms\n超过 120Hz 参考间隔（非掉帧）：%d 次\n估算回调调度缺口（非呈现丢帧）：%d 次\n低电量：%@ → %@\n温度等级：%d → %d\n口径：主线程 CADisplayLink 回调，不代表 GPU 实际呈现。包含静止时系统降频，不是‘最低帧率’承诺。",
                        maximum, h.samples, h.totalSeconds, h.averageFPS,
                        h.percentileMilliseconds(0.95), h.percentileMilliseconds(0.99), h.worstSeconds * 1000,
                        h.over120Budget, h.missedScheduledFrames,
                        startingPower ? "开" : "关", ProcessInfo.processInfo.isLowPowerModeEnabled ? "开" : "关",
                        startingThermal, ProcessInfo.processInfo.thermalState.rawValue)
    }

    @objc private func frame(_ link: CADisplayLink) {
        if previous > 0 {
            histogram.record(seconds: link.timestamp - previous,
                             scheduledSeconds: link.targetTimestamp - link.timestamp)
        }
        previous = link.timestamp
        if CACurrentMediaTime() >= deadline { stop() }
    }
}
