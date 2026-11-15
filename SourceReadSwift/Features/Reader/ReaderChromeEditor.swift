import SwiftUI

struct ReaderChromeEditor: View {
    @AppStorage("reader.headerFontSize") private var headerSize = 12.0
    @AppStorage("reader.headerTopGap") private var headerGap = 2.0
    @AppStorage("reader.headerOpacity") private var headerOpacity = 0.82
    @AppStorage("reader.headerLeftSlot") private var headerLeftRaw = ReaderChromeSlotContent.chapterTitle.rawValue
    @AppStorage("reader.headerCenterSlot") private var headerCenterRaw = ReaderChromeSlotContent.none.rawValue
    @AppStorage("reader.headerRightSlot") private var headerRightRaw = ReaderChromeSlotContent.none.rawValue
    @AppStorage("reader.footerHeight") private var footerHeight = ReaderTypographyDefaults.footerHeight
    @AppStorage("reader.footerLeftSlot") private var footerLeftRaw = ReaderChromeSlotContent.time.rawValue
    @AppStorage("reader.footerCenterSlot") private var footerCenterRaw = ReaderChromeSlotContent.chapterAndPercent.rawValue
    @AppStorage("reader.footerRightSlot") private var footerRightRaw = ReaderChromeSlotContent.pageAndBattery.rawValue
    @AppStorage("reader.chromeShowDivider") private var showDivider = false
    @AppStorage("reader.footerShowTime") private var showTime = true
    @AppStorage("reader.footerShowBatteryIcon") private var showBattery = true
    @AppStorage("reader.footerShowBatteryPercent") private var showPercent = true
    @AppStorage("reader.showSystemStatusBar") private var showSystem = false
    @AppStorage("reader.statusPosition") private var position = "bottom"
    @AppStorage("reader.allowsDuplicateTopStatus") private var duplicates = false
    @AppStorage("reader.contentExtendsIntoChrome") private var extendsContent = false
    @AppStorage("reader.menuPaperOpacity") private var menuOpacity = 0.97
    @AppStorage("reader.menuUsesWallpaper") private var wallpaper = false
    @AppStorage("reader.menuSurfaceStyle") private var surface = "system"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("页眉内容 · 左 / 中 / 右")
                    .font(.headline)
                slotRow(left: $headerLeftRaw, center: $headerCenterRaw, right: $headerRightRaw)
                Toggle("显示页眉页脚细分割线", isOn: $showDivider)
                slider("页眉字号", value: $headerSize, range: 9...18)
                slider("顶部间距", value: $headerGap, range: 0...24)
                slider("文字浓度", value: $headerOpacity, range: 0.35...1)
                Text("会同步为正文预留空间，不用手动留白避开页眉。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("页脚内容 · 左 / 中 / 右")
                    .font(.headline)
                slotRow(left: $footerLeftRaw, center: $footerCenterRaw, right: $footerRightRaw)
                BrandSegmentedControl("时间电量位置", selection: $position, options:
                            [("bottom", "页脚"), ("top", "页眉"), ("both", "两处")])
                Toggle("显示系统状态栏", isOn: $showSystem)
                Toggle("显示时间", isOn: $showTime)
                Toggle("显示电量图标", isOn: $showBattery)
                Toggle("显示电量百分比", isOn: $showPercent)
                Toggle("允许与系统顶部信息重复", isOn: $duplicates)
                slider("底部安全留白", value: $footerHeight, range: 40...180)
                Toggle("内容延伸至页眉页脚区域", isOn: $extendsContent)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("菜单纸面")
                    .font(.headline)
                BrandSegmentedControl("菜单材质", selection: $surface, options:
                            [("system", "系统材质"), ("paper", "阅读纸面")])
                Toggle("沿用阅读壁纸与纸纹", isOn: $wallpaper)
                if wallpaper && surface == "system" {
                    Text("沿用壁纸时使用阅读纸面；关闭后恢复系统玻璃。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                slider("纸面浓度", value: $menuOpacity, range: 0.85...1)
                    .disabled(!wallpaper)
                if !wallpaper {
                    Text("开启沿用壁纸后可调节纸面浓度。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("纸面风格会应用到阅读工具栏与设置容器，也会随整套装帧一起保存。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(AppTheme.accent)
    }

    private func slotRow(
        left: Binding<String>,
        center: Binding<String>,
        right: Binding<String>
    ) -> some View {
        HStack(spacing: 8) {
            slotMenu(label: "左侧", selection: left)
            slotMenu(label: "居中", selection: center)
            slotMenu(label: "右侧", selection: right)
        }
    }

    private func slotMenu(label: String, selection: Binding<String>) -> some View {
        let active = ReaderChromeSlotContent(rawValue: selection.wrappedValue) ?? .none
        return Menu {
            ForEach(ReaderChromeSlotContent.allCases) { option in
                Button {
                    selection.wrappedValue = option.rawValue
                    if option == .time || option == .timeAndBattery {
                        showTime = true
                    }
                    if (option == .battery || option == .timeAndBattery || option == .pageAndBattery),
                       !showBattery, !showPercent {
                        showBattery = true
                        showPercent = true
                    }
                } label: {
                    if option == active {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(active.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        ReaderSettingsContent {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(range.upperBound <= 1 ? "\(Int(value.wrappedValue * 100))%" : "\(Int(value.wrappedValue)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: value, in: range)
            }
        }
    }
}
