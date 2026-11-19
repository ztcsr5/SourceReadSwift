import SwiftUI

struct ReaderChromeEditor: View {
    var bookTitle: String = "纸间夜读"
    var chapterTitle: String = "第壹章 · 纸间入门指南"
    var pageProgressText: String = "12/38"
    var percentText: String = "31.6%"
    var chapterAndPercentText: String = "第壹章 · 31.6%"
    var paperRevision: UUID? = nil

    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("reader.chapterHeadingStyle") private var headingStyleRaw = ReaderPageChromeLayout.header.rawValue
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
    @AppStorage("reader.background") private var paperRaw = ReaderBackground.white.rawValue
    @AppStorage("reader.customWallpaperFillMode") private var fillRaw = ReaderWallpaperFillMode.fill.rawValue
    @AppStorage("reader.followSystemPaper") private var followSystemPaper = false
    @AppStorage("reader.inkOpacity") private var inkOpacity = 1.0
    @AppStorage("reader.customInkHex") private var customInkHexRaw = ""

    private var paper: ReaderBackground { ReaderBackground(rawValue: paperRaw) ?? .white }
    private var headingStyle: ReaderPageChromeLayout { ReaderPageChromeLayout(rawValue: headingStyleRaw) ?? .header }
    private var isNight: Bool {
        (paper != .custom && paper.isDark) || (followSystemPaper && systemColorScheme == .dark)
    }
    private var parsedCustomInkHex: UInt32? {
        let trimmed = customInkHexRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let hex = UInt32(trimmed.replacingOccurrences(of: "#", with: ""), radix: 16) else {
            return nil
        }
        return hex
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            liveChromeMirrorCard

            VStack(alignment: .leading, spacing: 8) {
                Text("章节标题呈现")
                    .font(.headline)
                BrandSegmentedControl("章节标题位置", selection: $headingStyleRaw, options: [
                    (ReaderPageChromeLayout.header.rawValue, "页眉+章首"),
                    (ReaderPageChromeLayout.inline.rawValue, "仅正文大题"),
                    (ReaderPageChromeLayout.hidden.rawValue, "全部隐藏")
                ])
                Text(headingStyle.help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("页眉三槽 · 左 / 中 / 右")
                    .font(.headline)
                slotRow(left: $headerLeftRaw, center: $headerCenterRaw, right: $headerRightRaw)
                Toggle("显示页眉页脚细分割线", isOn: $showDivider)
                    .editionToggleStyle(ink: AppTheme.accent, paper: AppTheme.card)
                slider("页眉字号", value: $headerSize, range: 9...18)
                slider("顶部间距", value: $headerGap, range: 0...24)
                slider("文字浓度", value: $headerOpacity, range: 0.35...1)
                Text("会同步为正文预留空间，不用手动留白避开页眉。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("页脚三槽 · 左 / 中 / 右")
                    .font(.headline)
                slotRow(left: $footerLeftRaw, center: $footerCenterRaw, right: $footerRightRaw)
                BrandSegmentedControl("时间电量位置", selection: $position, options:
                            [("bottom", "页脚"), ("top", "页眉"), ("both", "两处")])
                Toggle("显示系统状态栏", isOn: $showSystem)
                    .editionToggleStyle(ink: AppTheme.accent, paper: AppTheme.card)
                Toggle("显示时间", isOn: $showTime)
                    .editionToggleStyle(ink: AppTheme.accent, paper: AppTheme.card)
                Toggle("显示电量图标", isOn: $showBattery)
                    .editionToggleStyle(ink: AppTheme.accent, paper: AppTheme.card)
                Toggle("显示电量百分比", isOn: $showPercent)
                    .editionToggleStyle(ink: AppTheme.accent, paper: AppTheme.card)
                Toggle("允许与系统顶部信息重复", isOn: $duplicates)
                    .editionToggleStyle(ink: AppTheme.accent, paper: AppTheme.card)
                slider("底部留白", value: $footerHeight, range: 40...180)
                Toggle("内容延伸至页眉页脚区域", isOn: $extendsContent)
                    .editionToggleStyle(ink: AppTheme.accent, paper: AppTheme.card)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("菜单纸面")
                    .font(.headline)
                BrandSegmentedControl("菜单材质", selection: $surface, options:
                            [("system", "系统材质"), ("paper", "阅读纸面")])
                Toggle("沿用阅读壁纸与纸纹", isOn: $wallpaper)
                    .editionToggleStyle(ink: AppTheme.accent, paper: AppTheme.card)
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

    private var liveChromeMirrorCard: some View {
        let resolvedInk = paper.resolvedTextColor(isNight: isNight, customInkHex: parsedCustomInkHex, inkOpacity: inkOpacity)
        let headerLeft = ReaderChromeSlotContent(rawValue: headerLeftRaw) ?? .chapterTitle
        let headerCenter = ReaderChromeSlotContent(rawValue: headerCenterRaw) ?? .none
        let headerRight = ReaderChromeSlotContent(rawValue: headerRightRaw) ?? .none
        let footerLeft = ReaderChromeSlotContent(rawValue: footerLeftRaw) ?? .time
        let footerCenter = ReaderChromeSlotContent(rawValue: footerCenterRaw) ?? .chapterAndPercent
        let footerRight = ReaderChromeSlotContent(rawValue: footerRightRaw) ?? .pageAndBattery
        let safeBookTitle = bookTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "纸间夜读" : bookTitle
        let safeChapter = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "第壹章 · 纸间入门指南" : chapterTitle
        let slotContext = ReaderChromeSlotContext(
            chapterTitle: headingStyle == .hidden ? nil : safeChapter,
            bookTitle: safeBookTitle,
            pageProgressText: pageProgressText.isEmpty ? "12/38" : pageProgressText,
            percentText: percentText.isEmpty ? "31.6%" : percentText,
            chapterAndPercentText: chapterAndPercentText.isEmpty ? "\(safeChapter)  31.6%" : chapterAndPercentText,
            batterySymbolName: "battery.75",
            batteryPercentageText: "82%",
            showBatteryIcon: showBattery,
            showBatteryPercent: showPercent,
            showTime: showTime
        )
        let effectiveHeader = ReaderChromeSlotPolicy.effectiveHeaderSlots(
            left: headerLeft,
            center: headerCenter,
            right: headerRight,
            statusPosition: position,
            showTime: showTime,
            showBatteryIcon: showBattery,
            showBatteryPercent: showPercent
        )
        let bottomStatusVisible = position == "bottom" || position == "both"
        let effectiveFooterLeft: ReaderChromeSlotContent = (footerLeft == .time || footerLeft == .battery || footerLeft == .timeAndBattery)
            && !bottomStatusVisible ? .none : footerLeft
        let effectiveFooterRight: ReaderChromeSlotContent = (footerRight == .battery || footerRight == .timeAndBattery)
            && !bottomStatusVisible ? .none : footerRight

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("页眉＋页脚实时镜像")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(resolvedInk.opacity(0.68))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(resolvedInk.opacity(0.08), in: Capsule())
                Spacer(minLength: 4)
                Text(extendsContent ? "延伸正文开启" : "预留页边距")
                    .font(.caption2)
                    .foregroundStyle(resolvedInk.opacity(0.48))
            }

            VStack(alignment: .leading, spacing: 6) {
                ReaderThreeSlotChromeStrip(
                    left: effectiveHeader.left,
                    center: effectiveHeader.center,
                    right: effectiveHeader.right,
                    context: slotContext,
                    fontSize: CGFloat(ReaderHeadingPreferences.headerSize(headerSize)),
                    weight: .medium,
                    foreground: resolvedInk.opacity(ReaderHeadingPreferences.opacity(headerOpacity))
                )
                .frame(minHeight: 16)

                if showDivider {
                    Rectangle()
                        .fill(resolvedInk.opacity(0.14))
                        .frame(height: 0.5)
                }

                Text("　　长街尽头的灯火一盏接一盏熄灭，只余书案上一豆青焰静静跳动……")
                    .font(.footnote)
                    .foregroundStyle(resolvedInk.opacity(extendsContent ? 0.84 : 0.48))
                    .lineLimit(2)
                    .padding(.vertical, 2)

                if showDivider {
                    Rectangle()
                        .fill(resolvedInk.opacity(0.14))
                        .frame(height: 0.5)
                }

                ReaderThreeSlotChromeStrip(
                    left: effectiveFooterLeft,
                    center: footerCenter,
                    right: effectiveFooterRight,
                    context: slotContext,
                    fontSize: 11,
                    weight: .medium,
                    foreground: resolvedInk.opacity(0.68)
                )
                .frame(minHeight: 16)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                if paper == .custom, let image = ReaderCustomWallpaperStore.cachedWallpaper {
                    ReaderWallpaperView(
                        image: image,
                        fillMode: ReaderWallpaperFillMode(rawValue: fillRaw) ?? .fill,
                        adjustment: ReaderCustomWallpaperStore.adjustment,
                        isNight: isNight
                    ).id(paperRevision)
                } else {
                    ReaderPaperTextureView(background: paper, night: isNight)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(resolvedInk.opacity(0.14), lineWidth: 0.75)
            }
            .environment(\.colorScheme, isNight ? .dark : .light)
        }
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

    private func slotDisplayTitle(_ slot: ReaderChromeSlotContent) -> String {
        slot == .none ? "留空" : slot.title
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
                    let optionTitle = option == .none ? "留空（不显示）" : option.title
                    if option == active {
                        Label(optionTitle, systemImage: "checkmark")
                    } else {
                        Text(optionTitle)
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(slotDisplayTitle(active))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.down")
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
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(range.upperBound <= 1 ? "\(Int(value.wrappedValue * 100))%" : "\(Int(value.wrappedValue)) pt")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary.opacity(0.78))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(.primary.opacity(0.08), in: Capsule())
                }
                EditionSlider(value: value, range: range, ink: AppTheme.accent, paper: AppTheme.card)
            }
        }
    }
}
