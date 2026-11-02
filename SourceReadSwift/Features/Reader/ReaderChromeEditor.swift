import SwiftUI

struct ReaderChromeEditor: View {
    @AppStorage("reader.headerFontSize") private var headerSize = 12.0
    @AppStorage("reader.headerTopGap") private var headerGap = 2.0
    @AppStorage("reader.headerOpacity") private var headerOpacity = 0.82
    @AppStorage("reader.footerHeight") private var footerHeight = ReaderTypographyDefaults.footerHeight
    @AppStorage("reader.footerShowTime") private var showTime = true
    @AppStorage("reader.footerShowBatteryIcon") private var showBattery = true
    @AppStorage("reader.footerShowBatteryPercent") private var showPercent = true
    @AppStorage("reader.showSystemStatusBar") private var showSystem = false
    @AppStorage("reader.statusPosition") private var position = "bottom"
    @AppStorage("reader.allowsDuplicateTopStatus") private var duplicates = false
    @AppStorage("reader.menuPaperOpacity") private var menuOpacity = 0.97
    @AppStorage("reader.menuUsesWallpaper") private var wallpaper = false
    @AppStorage("reader.menuSurfaceStyle") private var surface = "system"
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("页眉 · 独立排版").font(.headline)
                slider("页眉字号", value: $headerSize, range: 9...18)
                slider("顶部间距", value: $headerGap, range: 0...24)
                slider("文字浓度", value: $headerOpacity, range: 0.35...1)
                Text("会同步为正文预留空间，不用手动留白避开页眉。") .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("页脚与系统状态栏").font(.headline)
                Picker("时间电量位置", selection: $position) {
                    Text("页脚").tag("bottom"); Text("页眉").tag("top"); Text("两处").tag("both")
                }.pickerStyle(.segmented)
                Toggle("显示系统状态栏", isOn: $showSystem)
                Toggle("显示时间", isOn: $showTime)
                Toggle("显示电量图标", isOn: $showBattery)
                Toggle("显示电量百分比", isOn: $showPercent)
                Toggle("允许与系统顶部信息重复", isOn: $duplicates)
                slider("底部安全留白", value: $footerHeight, range: 40...180)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("菜单纸面").font(.headline)
                Picker("菜单材质", selection: $surface) { Text("系统材质").tag("system"); Text("阅读纸面").tag("paper") }.pickerStyle(.segmented)
                Toggle("沿用阅读壁纸与纸纹", isOn: $wallpaper)
                if wallpaper && surface == "system" {
                    Text("沿用壁纸时使用阅读纸面；关闭后恢复系统玻璃。") .font(.caption).foregroundStyle(.secondary)
                }
                slider("纸面浓度", value: $menuOpacity, range: 0.85...1)
                    .disabled(!wallpaper)
                if !wallpaper { Text("开启沿用壁纸后可调节纸面浓度。") .font(.caption).foregroundStyle(.secondary) }
                Text("纸面风格会应用到阅读工具栏与设置容器，也会随整套装帧一起保存。") .font(.caption).foregroundStyle(.secondary)
            }
        }.tint(AppTheme.accent)
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        ReaderSettingsContent {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text(title); Spacer(); Text(range.upperBound <= 1 ? "\(Int(value.wrappedValue * 100))%" : "\(Int(value.wrappedValue)) pt").monospacedDigit().foregroundStyle(.secondary) }
                Slider(value: value, in: range)
            }
        }
    }
}
