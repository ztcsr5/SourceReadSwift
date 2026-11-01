import SwiftUI

/// Keep the full diagnostics, but don't spend the settings landing page on
/// six mostly-zero development counters and a long explanatory footer.
struct ReaderPerformanceDiagnosticsView: View {
    @State private var perfRefreshToken = UUID()

    var body: some View {
        List {
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
                    Text("滚动回调耗时小于 2ms 说明瓶颈在界面重建，大于 6ms 说明在文字排版；掉帧率超过 5% 就是肉眼可见的卡。滚动几章后回来看数字。")
                }
                .id(perfRefreshToken)

        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("阅读器性能")
        .navigationBarTitleDisplayMode(.inline)
    }
}
