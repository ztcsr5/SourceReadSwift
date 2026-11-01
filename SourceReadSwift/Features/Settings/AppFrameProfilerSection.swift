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
            Text("全应用帧时间")
        } footer: {
            Text("开始后返回主页、发现、目录或漫画页持续操作，再回来查看 P95/P99。120fps 的单帧预算为 8.33ms；完整呈现与 GPU 卡顿需在真机用 Instruments 的 Animation Hitches 验证。静止、低电量与发热时系统会降低刷新率。")
        }
        .listRowBackground(AppThemeRowSurface())
    }
}
