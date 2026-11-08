import SwiftUI
import QuartzCore

/// 采样期间的实时帧率浮层：只显示，不参与布局测量。
/// 数据来自 AppFrameProfiler 的 CADisplayLink 回调，4 Hz 刷新一次，避免自身影响帧率。
struct ReaderFrameHUD: View {
    @ObservedObject private var profiler = AppFrameProfiler.shared

    var body: some View {
        if profiler.isRecording {
            HStack(spacing: 10) {
                Text(String(format: "%.0f Hz", profiler.liveHertz))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                Text(String(format: "p99 %.1f ms", profiler.liveP99Milliseconds))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Text("期望 \(profiler.screenMaximumHertz) Hz")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.62), in: Capsule())
            .padding(.top, 8)
            .padding(.leading, 12)
            .allowsHitTesting(false)
            .accessibilityIdentifier("reader.frameHUD")
        }
    }
}
