import SwiftUI

/// Keep the full diagnostics, but don't spend the settings landing page on
/// six mostly-zero development counters and a long explanatory footer.
struct ReaderPerformanceDiagnosticsView: View {
    @State private var perfRefreshToken = UUID()

    var body: some View {
        List {
                AppFrameProfilerSection()
                Section {
                    let perf = ReaderScrollPerfMeter.snapshot
                    HStack {
                        Text("滚动回调平均耗时")
                        Spacer()
                        Text(String(format: "%.2f ms", perf.averageMilliseconds))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("最差一次")
                        Spacer()
                        Text(String(format: "%.2f ms", perf.worstMilliseconds))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("样本帧数")
                        Spacer()
                        Text("\(perf.frames)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    let frameRate = ReaderFrameRateSampler.snapshot
                    HStack {
                        Text("平均帧率")
                        Spacer()
                        Text(String(format: "%.1f fps", frameRate.averageFPS))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("掉帧率")
                        Spacer()
                        Text(String(format: "%.1f%%（%d 帧）", frameRate.droppedRatio * 100, frameRate.droppedFrames))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("出帧样本")
                        Spacer()
                        Text("\(frameRate.frames)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Button("清零重新采样") {
                        ReaderScrollPerfMeter.reset()
                        ReaderFrameRateSampler.reset()
                        perfRefreshToken = UUID()
                    }
                } header: {
                    Text("阅读器性能（诊断）")
                } footer: {
                    Text("阅读器局部采样，仅用于辅助定位。回调耗时不等于整帧耗时，不能单凭这个数字判断是重建、排版还是 GPU 瓶颈。使用上方全局采样和真机 Instruments 交叉验证。")
                }
                .listRowBackground(AppThemeRowSurface())
                .id(perfRefreshToken)

        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("阅读器性能")
        .navigationBarTitleDisplayMode(.inline)
    }
}
