import SwiftUI

/// Settings-tab entry for the reading typography that used to be reachable only
/// from inside an open book.
///
/// Every control writes the same `reader.*` key the reader itself observes, so
/// the next book opens with these values without any extra hand-off. This screen
/// deliberately does not instantiate `ReaderSettingsWorkbench`: that type needs
/// a live reader context (background, bottom inset, chapter state).
struct ReaderSettingsPage: View {
    @AppStorage("reader.fontFamily") private var fontFamily = ReaderFontFamily.system.rawValue
    @AppStorage("reader.fontSize") private var fontSize = ReaderTypographyDefaults.fontSize
    @AppStorage("reader.lineSpacing") private var lineSpacing = ReaderTypographyDefaults.lineSpacing
    @AppStorage("reader.letterSpacing") private var letterSpacing = ReaderTypographyDefaults.letterSpacing
    @AppStorage("reader.paragraphSpacing") private var paragraphSpacing = ReaderTypographyDefaults.paragraphSpacing
    @AppStorage("reader.paragraphIndent") private var paragraphIndent = ReaderTypographyDefaults.paragraphIndent
    @AppStorage("reader.pagePadding") private var pagePadding = ReaderTypographyDefaults.pagePadding

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
    @AppStorage("reader.footerHeight") private var footerHeight = ReaderTypographyDefaults.footerHeight
    @AppStorage("reader.footerShowTime") private var footerShowTime = true
    @AppStorage("reader.footerShowBatteryIcon") private var footerShowBatteryIcon = true
    @AppStorage("reader.footerShowBatteryPercent") private var footerShowBatteryPercent = true

    @AppStorage("reader.background") private var background = ReaderBackground.white.rawValue
    @AppStorage("reader.customWallpaperFillMode") private var wallpaperFillMode = ReaderWallpaperFillMode.fill.rawValue
    @AppStorage("reader.menuSurfaceStyle") private var menuSurfaceStyle = "system"
    @AppStorage("reader.menuUsesWallpaper") private var menuUsesWallpaper = false
    @AppStorage("reader.menuPaperOpacity") private var menuPaperOpacity = 0.97

    @State private var confirmsReset = false

    var body: some View {
        Form {
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

    private var bodySection: some View {
        Section {
            Picker("正文字体", selection: $fontFamily) {
                ForEach(ReaderFontFamily.allCases) { family in
                    Text(family.title).tag(family.rawValue)
                }
            }
            .accessibilityIdentifier("readerSettings.fontFamily")
            numberRow("字号", value: $fontSize, range: 12...60, unit: "pt")
            numberRow("行距", value: $lineSpacing, range: 0...40, unit: "pt")
            numberRow("字距", value: $letterSpacing, range: 0...10, unit: "pt")
            numberRow("段距", value: $paragraphSpacing, range: 0...60, unit: "pt")
            numberRow("首行缩进", value: $paragraphIndent, range: 0...100, unit: "pt")
            numberRow("左右边距", value: $pagePadding, range: 0...100, unit: "pt")
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
            numberRow("页脚留白", value: $footerHeight, range: 0...200, unit: "pt")
            Toggle("页脚显示时间", isOn: $footerShowTime)
            Toggle("页脚显示电量图标", isOn: $footerShowBatteryIcon)
            Toggle("页脚显示电量百分比", isOn: $footerShowBatteryPercent)
        } header: {
            Text("页眉与页脚")
        } footer: {
            Text("页脚留白会同步为正文底部让出空间，避免最后一行被页码压住。")
        }
        .listRowBackground(AppThemeRowSurface())
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
        } header: {
            Text("纸面与菜单")
        } footer: {
            Text("自定义壁纸请阅读页内的壁纸编辑器导入；这里只控制已导入壁纸的填充方式。")
        }
        .listRowBackground(AppThemeRowSurface())
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
