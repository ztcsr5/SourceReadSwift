import SwiftUI
import UIKit

/// Settings-tab entry for the reading typography that used to be reachable only
/// from inside an open book.
///
/// Every control writes the same `reader.*` key the reader itself observes, so
/// the next book opens with these values without any extra hand-off. This screen
/// deliberately does not instantiate `ReaderSettingsWorkbench`: that type needs
/// a live reader context (background, bottom inset, chapter state).
struct ReaderSettingsPage: View {
    @AppStorage("reader.fontFamily") private var fontFamily = ReaderFontFamily.system.rawValue
    @AppStorage("reader.fontWeight") private var fontWeight = ReaderBodyFontWeight.regular.rawValue
    @AppStorage("reader.fontSize") private var fontSize = ReaderTypographyDefaults.fontSize
    @AppStorage("reader.lineSpacing") private var lineSpacing = ReaderTypographyDefaults.lineSpacing
    @AppStorage("reader.letterSpacing") private var letterSpacing = ReaderTypographyDefaults.letterSpacing
    @AppStorage("reader.paragraphSpacing") private var paragraphSpacing = ReaderTypographyDefaults.paragraphSpacing
    @AppStorage("reader.paragraphIndent") private var paragraphIndent = ReaderTypographyDefaults.paragraphIndent
    @AppStorage("reader.pagePadding") private var pagePadding = ReaderTypographyDefaults.pagePadding
    @AppStorage("reader.verticalPadding") private var verticalPadding = 0.0
    @AppStorage("reader.textAlignment") private var textAlignment = ReaderTextAlignment.smart.rawValue
    @AppStorage("reader.smartLineCleanup") private var smartLineCleanup = false
    @AppStorage("reader.traditionalChineseEnabled") private var traditionalChineseEnabled = false

    @AppStorage("reader.chapterHeadingStyle") private var headingStyle = ReaderPageChromeLayout.header.rawValue
    @AppStorage("reader.chapterTitleFamily") private var chapterTitleFamily = ""
    @AppStorage("reader.chapterTitleBold") private var chapterTitleBold = true
    @AppStorage("reader.chapterTitleSize") private var chapterTitleSize = 0.0
    @AppStorage("reader.titleSpacing") private var titleSpacing = ReaderTypographyDefaults.titleSpacing
    @AppStorage("reader.chapterDecoration") private var chapterDecoration = ReaderChapterDecoration.none.rawValue
    @AppStorage("reader.chapterAlignment") private var chapterAlignment = ReaderChapterAlignment.leading.rawValue

    @AppStorage("reader.headerFontSize") private var headerFontSize = 12.0
    @AppStorage("reader.headerTopGap") private var headerTopGap = 2.0
    @AppStorage("reader.headerOpacity") private var headerOpacity = 0.82
    @AppStorage("reader.headerLeftSlot") private var headerLeftSlotRaw = ReaderChromeSlotContent.chapterTitle.rawValue
    @AppStorage("reader.headerCenterSlot") private var headerCenterSlotRaw = ReaderChromeSlotContent.none.rawValue
    @AppStorage("reader.headerRightSlot") private var headerRightSlotRaw = ReaderChromeSlotContent.none.rawValue
    @AppStorage("reader.footerHeight") private var footerHeight = ReaderTypographyDefaults.footerHeight
    @AppStorage("reader.footerLeftSlot") private var footerLeftSlotRaw = ReaderChromeSlotContent.time.rawValue
    @AppStorage("reader.footerCenterSlot") private var footerCenterSlotRaw = ReaderChromeSlotContent.chapterAndPercent.rawValue
    @AppStorage("reader.footerRightSlot") private var footerRightSlotRaw = ReaderChromeSlotContent.pageAndBattery.rawValue
    @AppStorage("reader.chromeShowDivider") private var chromeShowDivider = false
    @AppStorage("reader.footerShowTime") private var footerShowTime = true
    @AppStorage("reader.footerShowBatteryIcon") private var footerShowBatteryIcon = true
    @AppStorage("reader.footerShowBatteryPercent") private var footerShowBatteryPercent = true
    @ObservedObject private var highlightRuleStore = ReaderHighlightRuleStore.shared

    @AppStorage("reader.background") private var background = ReaderBackground.white.rawValue
    @AppStorage("reader.customWallpaperFillMode") private var wallpaperFillMode = ReaderWallpaperFillMode.fill.rawValue
    @AppStorage("reader.menuSurfaceStyle") private var menuSurfaceStyle = "system"
    @AppStorage("reader.menuUsesWallpaper") private var menuUsesWallpaper = false
    @AppStorage("reader.menuPaperOpacity") private var menuPaperOpacity = 0.97
    @AppStorage("reader.followSystemPaper") private var followSystemPaper = true
    @AppStorage("reader.inkOpacity") private var inkOpacity = 1.0
    @AppStorage("reader.customInkHex") private var customInkHex = ""
    @AppStorage("reader.customFontPostScriptName") private var customFontName = ""
    @Environment(\.colorScheme) private var scheme

    @State private var confirmsReset = false

    var body: some View {
        Form {
            previewAndPresets
            bodySection
            headingSection
            chromeSection
            surfaceSection
            Section {
                Button("恢复默认排版") { confirmsReset = true }
                    .foregroundStyle(.red)
            } footer: {
                Text("只重置本页的字号、间距、纸张与页眉页脚；不改变书籍、阅读进度、翻页模式或壁纸文件。")
            }
            .listRowBackground(AppThemeRowSurface())
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("阅读排版")
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppTheme.accent)
        .confirmationDialog("把阅读排版恢复为默认值？", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("恢复默认", role: .destructive) { resetToDefaults() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前打开的书会在下次进入阅读时使用新排版。")
        }
    }

    private var previewAndPresets: some View {
        Section {
            let paper = ReaderBackground(rawValue: background) ?? .white
            let night = paper.isDark || (followSystemPaper && scheme == .dark)
            let inkHex = UInt32(customInkHex, radix: 16)
            let resolvedInk = paper.resolvedTextColor(isNight: night, customInkHex: inkHex, inkOpacity: inkOpacity)
            let family = ReaderFontFamily(rawValue: fontFamily) ?? .system
            let weight = ReaderBodyFontWeight(rawValue: fontWeight) ?? .regular
            let alignment = ReaderTextAlignment(rawValue: textAlignment) ?? .smart
            let chromeStyle = ReaderPageChromeLayout(rawValue: headingStyle) ?? .header
            let headerLeft = ReaderChromeSlotContent(rawValue: headerLeftSlotRaw) ?? .chapterTitle
            let headerCenter = ReaderChromeSlotContent(rawValue: headerCenterSlotRaw) ?? .none
            let headerRight = ReaderChromeSlotContent(rawValue: headerRightSlotRaw) ?? .none
            let footerLeft = ReaderChromeSlotContent(rawValue: footerLeftSlotRaw) ?? .time
            let footerCenter = ReaderChromeSlotContent(rawValue: footerCenterSlotRaw) ?? .chapterAndPercent
            let footerRight = ReaderChromeSlotContent(rawValue: footerRightSlotRaw) ?? .pageAndBattery
            let slotContext = ReaderChromeSlotContext(
                chapterTitle: chromeStyle == .hidden ? nil : "第十二章 · 夜雨微凉",
                bookTitle: "纸间示范集",
                pageProgressText: "3/18",
                percentText: "16%",
                chapterAndPercentText: "第十二章 · 夜雨微凉  16%",
                batterySymbolName: "battery.75",
                batteryPercentageText: "82%",
                showBatteryIcon: footerShowBatteryIcon,
                showBatteryPercent: footerShowBatteryPercent,
                showTime: footerShowTime
            )
            let headingAlign = ReaderChapterAlignment(rawValue: chapterAlignment) ?? .leading
            let decoration = ReaderChapterDecoration(rawValue: chapterDecoration) ?? .none
            let headingFamily = ReaderFontFamily(rawValue: chapterTitleFamily) ?? family
            let headingAlignment: Alignment = headingAlign == .center ? .center : (headingAlign == .trailing ? .trailing : .leading)
            let clampedBodySize = min(max(fontSize, 12), 60)

            VStack(alignment: .leading, spacing: 8) {
                if headerLeft != .none || headerCenter != .none || headerRight != .none {
                    VStack(spacing: 4) {
                        ReaderThreeSlotChromeStrip(
                            left: headerLeft,
                            center: headerCenter,
                            right: headerRight,
                            context: slotContext,
                            fontSize: CGFloat(ReaderHeadingPreferences.headerSize(headerFontSize)),
                            weight: .medium,
                            foreground: resolvedInk.opacity(ReaderHeadingPreferences.opacity(headerOpacity))
                        )
                        if chromeShowDivider {
                            Rectangle()
                                .fill(resolvedInk.opacity(0.10))
                                .frame(height: 0.5)
                        }
                    }
                }

                if chromeStyle != .hidden {
                    VStack(alignment: headingAlign == .center ? .center : (headingAlign == .trailing ? .trailing : .leading), spacing: 4) {
                        if decoration != .none {
                            ReaderChapterMotif(decoration: decoration, width: 112)
                                .foregroundStyle(resolvedInk)
                        }
                        Text("第十二章 · 夜雨微凉")
                            .font(
                                headingFamily.swiftUIFont(
                                    size: min(CGFloat(ReaderHeadingPreferences.titleSize(custom: chapterTitleSize, body: fontSize)), 26),
                                    weight: chapterTitleBold ? .bold : .regular,
                                    customPostScriptName: customFontName
                                )
                            )
                            .foregroundStyle(resolvedInk)
                            .multilineTextAlignment(headingAlign.swiftUI)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: headingAlignment)
                }

                ReaderTypographySample(
                    font: family.uiFont(ofSize: clampedBodySize, weight: weight.uiWeight, customPostScriptName: customFontName),
                    boldFont: family.uiFont(ofSize: clampedBodySize, weight: .semibold, customPostScriptName: customFontName),
                    ink: UIColor(resolvedInk),
                    layout: .init(
                        alignment: alignment,
                        lineSpacing: lineSpacing,
                        letterSpacing: letterSpacing,
                        paragraphSpacing: paragraphSpacing,
                        paragraphIndent: paragraphIndent
                    ),
                    highlightRules: ReaderHighlightMatcher.activeRules(from: highlightRuleStore.rules, bookTitle: "", sourceURL: ""),
                    isNight: night
                )
                .accessibilityLabel("实时排版样张，\(alignment.title)，字号 \(Int(fontSize))")
                .accessibilityIdentifier("readerSettings.typographySample")

                if footerLeft != .none || footerCenter != .none || footerRight != .none {
                    VStack(spacing: 4) {
                        if chromeShowDivider {
                            Rectangle()
                                .fill(resolvedInk.opacity(0.10))
                                .frame(height: 0.5)
                        }
                        ReaderThreeSlotChromeStrip(
                            left: footerLeft,
                            center: footerCenter,
                            right: footerRight,
                            context: slotContext,
                            fontSize: 10,
                            weight: .medium,
                            foreground: resolvedInk.opacity(0.45)
                        )
                    }
                }
            }
            .padding(.horizontal, min(max(pagePadding, 12), 42))
            .padding(.vertical, max(12, min(verticalPadding, 24)))
            .frame(maxWidth: .infinity)
            .background(paper.color(isNight: night), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.1), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            ForEach(ReaderTypographyPreset.allCases) { preset in
                Button {
                    applyPreset(preset)
                } label: {
                    HStack {
                        Label(preset.title, systemImage: "textformat.size")
                        Spacer(minLength: 8)
                        Text(preset.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(AppPressStyle())
                .accessibilityIdentifier("readerSettings.preset." + preset.rawValue)
            }
        } header: {
            Text("实时样张与排版预设")
        } footer: {
            Text("预设只替换字号、间距和边距。字体、翻页方式、书签和阅读位置保持原样。")
        }
        .listRowBackground(AppThemeRowSurface())
    }

    private func applyPreset(_ preset: ReaderTypographyPreset) {
        fontSize = preset.fontSize
        lineSpacing = preset.lineSpacing
        paragraphSpacing = preset.paragraphSpacing
        paragraphIndent = preset.paragraphIndent
        pagePadding = preset.pagePadding
        verticalPadding = preset.verticalPadding
    }

    private var bodySection: some View {
        Section {
            Picker("正文字体", selection: $fontFamily) {
                ForEach(ReaderFontFamily.allCases) { family in
                    Text(family.title).tag(family.rawValue)
                }
            }
            .accessibilityIdentifier("readerSettings.fontFamily")
            Picker("正文字重", selection: $fontWeight) {
                ForEach(ReaderBodyFontWeight.allCases) { weight in
                    Text(weight.title).tag(weight.rawValue)
                }
            }
            numberRow("字号", value: $fontSize, range: 12...60, unit: "pt")
            numberRow("行距", value: $lineSpacing, range: 0...40, unit: "pt")
            numberRow("字距", value: $letterSpacing, range: 0...10, unit: "pt")
            numberRow("段距", value: $paragraphSpacing, range: 0...60, unit: "pt")
            numberRow("首行缩进", value: $paragraphIndent, range: 0...100, unit: "pt")
            numberRow("左右边距", value: $pagePadding, range: 0...100, unit: "pt")
            numberRow("上下边距", value: $verticalPadding, range: 0...36, unit: "pt")
            Picker("对齐排版", selection: $textAlignment) {
                ForEach(ReaderTextAlignment.allCases) { alignment in
                    Text(alignment.title).tag(alignment.rawValue)
                }
            }
            Toggle("智能分段/空行净化", isOn: $smartLineCleanup)
            Toggle("繁体中文（简转繁）", isOn: $traditionalChineseEnabled)
        } header: {
            Text("正文")
        } footer: {
            Text("首行缩进 40 pt 约等于两个 20 pt 汉字；行距与段距会直接写进 WebKit 排版，改动后翻回上一页即可看到。")
        }
        .listRowBackground(AppThemeRowSurface())
    }

    private var headingSection: some View {
        Section {
            Picker("章节标题位置", selection: $headingStyle) {
                ForEach(ReaderPageChromeLayout.allCases) { layout in
                    Text(layout.title).tag(layout.rawValue)
                }
            }
            .accessibilityIdentifier("readerSettings.headingStyle")
            Picker("标题字体", selection: $chapterTitleFamily) {
                Text("跟随正文").tag("")
                ForEach(ReaderFontFamily.allCases) { family in
                    Text(family.title).tag(family.rawValue)
                }
            }
            Toggle("标题加粗", isOn: $chapterTitleBold)
            numberRow("标题字号（0 为自动）", value: $chapterTitleSize, range: 0...60, unit: "pt")
            numberRow("标题下方间距", value: $titleSpacing, range: 0...100, unit: "pt")
            Picker("章首装饰", selection: $chapterDecoration) {
                ForEach(ReaderChapterDecoration.allCases, id: \.rawValue) { decoration in
                    Text(decoration.title).tag(decoration.rawValue)
                }
            }
            Picker("标题对齐", selection: $chapterAlignment) {
                ForEach(ReaderChapterAlignment.allCases, id: \.rawValue) { alignment in
                    Text(alignment.title).tag(alignment.rawValue)
                }
            }
        } header: {
            Text("章节标题")
        } footer: {
            Text("页眉模式下每页顶部显示小章节名；正文大标题只在章节第一页出现。")
        }
        .listRowBackground(AppThemeRowSurface())
    }

    private var chromeSection: some View {
        Section {
            numberRow("页眉字号", value: $headerFontSize, range: 9...18, unit: "pt")
            numberRow("页眉上间距", value: $headerTopGap, range: 0...24, unit: "pt")
            numberRow("页眉浓度", value: $headerOpacity, range: 0.35...1, percentStyle: true)
            slotPicker("页眉左侧", selection: slotBinding($headerLeftSlotRaw))
            slotPicker("页眉居中", selection: slotBinding($headerCenterSlotRaw))
            slotPicker("页眉右侧", selection: slotBinding($headerRightSlotRaw))
            numberRow("页脚留白", value: $footerHeight, range: 0...200, unit: "pt")
            slotPicker("页脚左侧", selection: slotBinding($footerLeftSlotRaw))
            slotPicker("页脚居中", selection: slotBinding($footerCenterSlotRaw))
            slotPicker("页脚右侧", selection: slotBinding($footerRightSlotRaw))
            Toggle("显示页眉页脚细分割线", isOn: $chromeShowDivider)
            Toggle("页脚显示时间", isOn: $footerShowTime)
            Toggle("页脚显示电量图标", isOn: $footerShowBatteryIcon)
            Toggle("页脚显示电量百分比", isOn: $footerShowBatteryPercent)
        } header: {
            Text("页眉与页脚")
        } footer: {
            Text("页脚留白会同步为正文底部让出空间，避免最后一行被页码压住；三栏槽位支持自定义页眉与页脚显示内容。")
        }
        .listRowBackground(AppThemeRowSurface())
    }

    private func slotPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ReaderChromeSlotContent.allCases) { option in
                Text(option.title).tag(option.rawValue)
            }
        }
    }

    private func slotBinding(_ storage: Binding<String>) -> Binding<String> {
        Binding(
            get: { storage.wrappedValue },
            set: { newValue in
                storage.wrappedValue = newValue
                guard let slot = ReaderChromeSlotContent(rawValue: newValue) else { return }
                if slot == .time || slot == .timeAndBattery {
                    footerShowTime = true
                }
                if (slot == .battery || slot == .timeAndBattery || slot == .pageAndBattery),
                   !footerShowBatteryIcon, !footerShowBatteryPercent {
                    footerShowBatteryIcon = true
                    footerShowBatteryPercent = true
                }
            }
        )
    }

    private var surfaceSection: some View {
        Section {
            Picker("阅读纸张", selection: $background) {
                ForEach(ReaderBackground.allCases) { paper in
                    Text(paper.title).tag(paper.rawValue)
                }
            }
            .accessibilityIdentifier("readerSettings.background")
            Picker("壁纸填充", selection: $wallpaperFillMode) {
                ForEach(ReaderWallpaperFillMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            Picker("菜单材质", selection: $menuSurfaceStyle) {
                Text("系统材质").tag("system")
                Text("阅读纸面").tag("paper")
            }
            Toggle("菜单沿用壁纸", isOn: $menuUsesWallpaper)
            numberRow("菜单纸面浓度", value: $menuPaperOpacity, range: 0.85...1, percentStyle: true)
                .disabled(!menuUsesWallpaper)
            Toggle("正文纸张随系统深色切换", isOn: $followSystemPaper)
            numberRow("正文墨色对比度", value: $inkOpacity, range: 0.55...1, percentStyle: true)
            ColorPicker("自定正文墨色", selection: customInkBinding, supportsOpacity: false)
            if !customInkHex.isEmpty {
                Button("恢复纸张默认墨色") { customInkHex = "" }
            }
        } header: {
            Text("纸面与菜单")
        } footer: {
            Text("自定义壁纸请阅读页内的壁纸编辑器导入；这里只控制已导入壁纸的填充方式。")
        }
        .listRowBackground(AppThemeRowSurface())
    }

    private var customInkBinding: Binding<Color> {
        Binding(get: {
            let paper = ReaderBackground(rawValue: background) ?? .white
            return paper.resolvedTextColor(isNight: paper.isDark || (followSystemPaper && scheme == .dark),
                customInkHex: UInt32(customInkHex, radix: 16))
        }, set: { picked in
            if let hex = AppTheme.hex(picked) { customInkHex = hex }
        })
    }

    private func numberRow(_ title: String, value: Binding<Double>,
                           range: ClosedRange<Double>, unit: String = "",
                           percentStyle: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(percentStyle ? "\(Int((value.wrappedValue * 100).rounded()))%"
                                  : "\(Int(value.wrappedValue.rounded())) \(unit)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { min(max(value.wrappedValue, range.lowerBound), range.upperBound) },
                set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
            ), in: range)
        }
    }

    private func resetToDefaults() {
        let defaults = ReaderBindingPreferences.defaults
        for key in ReaderBindingPreferences.appearanceKeys {
            guard let fallback = defaults[key] else { continue }
            UserDefaults.standard.set(fallback.propertyListValue, forKey: key)
        }
        UserDefaults.standard.set(UUID().uuidString, forKey: "reader.bindingRevision")
    }
}
