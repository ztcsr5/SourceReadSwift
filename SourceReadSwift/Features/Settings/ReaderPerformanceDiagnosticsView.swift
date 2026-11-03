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
                        Text("诊断回调样本")
                        Spacer()
                        Text("\(perf.frames)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Button("清零诊断回调记录") {
                        ReaderScrollPerfMeter.reset()
                        ReaderFrameRateSampler.reset()
                        perfRefreshToken = UUID()
                    }
                } header: {
                    Text("阅读器性能（诊断）")
                } footer: {
                    Text("仅在上方显式诊断窗口内采集，新诊断会清零回调记录。这里是业务回调耗时，不是整帧耗时或显示帧率；不能单凭它判断是重建、排版还是 GPU 瓶颈。")
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
