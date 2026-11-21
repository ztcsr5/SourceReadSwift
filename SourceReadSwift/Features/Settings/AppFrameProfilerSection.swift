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
            Text("仅点击开始后采样，最多持续 30 秒；离开此页可测试其他页面，退后台或锁屏即停止。按设备上限请求回调（最高 120 Hz，低电量最高 60 Hz），报告同时记录请求值与应用 Bundle 高刷开关（容器内不等于宿主配置）。请求值不是实际帧率，主线程停顿会如实计入间隔；GPU 呈现仍需真机 Instruments 验证。")
        }
        .listRowBackground(AppThemeRowSurface())
    }
}
