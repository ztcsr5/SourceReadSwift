import SwiftUI

struct AppFrameProfilerSection: View {
    @ObservedObject private var profiler = AppFrameProfiler.shared
    var body: some View {
        Section {
            Button(profiler.isRecording ? "结束全局采样" : "开始 30 秒全局采样") {
                if profiler.isRecording { profiler.stop() } else { profiler.start() }
            }
            Text(profiler.report).font(.caption.monospaced()).textSelection(.enabled)
            Button("复制全局采样报告") { UIPasteboard.general.string = profiler.report }
        } header: {
            Text("显式诊断 · 主线程回调节奏")
        } footer: {
            Text("仅点击开始后采样。离开此页可测试其他页面，最多持续 30 秒；手动结束、退后台或锁屏即停止，回到前台不会自动恢复。采样会按屏幕上限请求帧（最高 120 Hz），回调频率降低即表示主线程/合成器掉帧。这里测的是回调节奏，不是 GPU 呈现；实际呈现与 GPU 卡顿仍需真机 Instruments 验证。")
        }
        .listRowBackground(AppThemeRowSurface())
    }
}
