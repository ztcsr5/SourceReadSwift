import SwiftUI

/// Uses real reader bindings so closing the settings never recreates a page or loses its zoom state.
struct ComicReaderSettingsView: View {
    struct Preferences {
        let mode: Binding<ComicReadingMode>
        let continuous: Binding<Bool>
        let reducedQuality: Binding<Bool>
        let disablesDoubleTap: Binding<Bool>
        let hidesBars: Binding<Bool>
        let canvas: Binding<String>
        let brightness: Binding<Double>
        let systemStatus: Binding<Bool>
        let pageStatus: Binding<String>
        let chromeStyle: Binding<String>
        let headerLeftSlot: Binding<String>
        let headerCenterSlot: Binding<String>
        let headerRightSlot: Binding<String>
        let footerLeftSlot: Binding<String>
        let footerCenterSlot: Binding<String>
        let footerRightSlot: Binding<String>
        let chromeFontSize: Binding<Double>
        let chromeOpacity: Binding<Double>
        let disablesQuickActions: Binding<Bool>
        let reverseTapZones: Binding<Bool>
        let transitions: Binding<Bool>
        let preloadPages: Binding<Int>
        let stripMargins: Binding<Bool>
        let marginPercent: Binding<Int>
        let marginDirection: Binding<String>
    }

    struct ChapterActions {
        let previous: (() -> Void)?
        let next: (() -> Void)?
        let download: (() -> Void)?
        let isDownloading: Bool
    }

    let preferences: Preferences
    let chapter: ChapterActions
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Route] = []

    private enum Route: Hashable { case readingMode }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section("阅读") {
                    NavigationLink(value: Route.readingMode) {
                        LabeledContent("阅读模式", value: preferences.mode.wrappedValue.rawValue)
                    }
                    .accessibilityIdentifier("comic.settings.mode")
                    Toggle("降低图片品质", isOn: preferences.reducedQuality)
                    Toggle("禁用双击缩放", isOn: preferences.disablesDoubleTap)
                    Toggle("滑动时隐藏栏", isOn: preferences.hidesBars)
                    Picker("背景颜色", selection: preferences.canvas) {
                        ForEach(ComicCanvas.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .pickerStyle(.navigationLink)
                    Slider(value: preferences.brightness, in: 0.2...1) { Text("漫画亮度") }
                        .accessibilityIdentifier("comic.settings.brightness")
                }
                Section("点击区域与翻页") {
                    Toggle("禁用快捷操作", isOn: preferences.disablesQuickActions)
                    Toggle("反转点击区域", isOn: preferences.reverseTapZones)
                        .disabled(preferences.disablesQuickActions.wrappedValue || preferences.mode.wrappedValue == .vertical)
                    Toggle("点按翻页动画", isOn: preferences.transitions)
                        .disabled(preferences.mode.wrappedValue == .vertical)
                    Stepper(value: preferences.preloadPages, in: ComicDisplayOptions.prefetchPageRange) {
                        LabeledContent("预加载页数", value: "\(preferences.preloadPages.wrappedValue)")
                    }
                }
                Section("条漫") {
                    Toggle("连续上下滚动", isOn: preferences.continuous)
                        .accessibilityIdentifier("comic.settings.continuous")
                    Toggle("黑边", isOn: preferences.stripMargins)
                    Stepper(value: preferences.marginPercent, in: ComicDisplayOptions.marginRange) {
                        LabeledContent("填充比例", value: "\(preferences.marginPercent.wrappedValue)%")
                    }
                    .disabled(!preferences.stripMargins.wrappedValue)
                    Picker("填充方向", selection: preferences.marginDirection) {
                        ForEach(ComicStripMarginDirection.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .pickerStyle(.navigationLink)
                    .disabled(!preferences.stripMargins.wrappedValue)
                }
                Section("页眉与页脚") {
                    Toggle("显示系统状态栏", isOn: preferences.systemStatus)
                    Picker("显示区域", selection: preferences.pageStatus) {
                        Text("仅页脚").tag("bottom")
                        Text("仅页眉").tag("top")
                        Text("页眉和页脚").tag("both")
                        Text("不显示").tag("none")
                    }
                    .pickerStyle(.navigationLink)
                    Picker("外观样式", selection: preferences.chromeStyle) {
                        ForEach(ComicChromeStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    if preferences.pageStatus.wrappedValue == "top" || preferences.pageStatus.wrappedValue == "both" {
                        slotPicker("页眉左侧", selection: preferences.headerLeftSlot)
                        slotPicker("页眉居中", selection: preferences.headerCenterSlot)
                        slotPicker("页眉右侧", selection: preferences.headerRightSlot)
                    }
                    if preferences.pageStatus.wrappedValue == "bottom" || preferences.pageStatus.wrappedValue == "both" {
                        slotPicker("页脚左侧", selection: preferences.footerLeftSlot)
                        slotPicker("页脚居中", selection: preferences.footerCenterSlot)
                        slotPicker("页脚右侧", selection: preferences.footerRightSlot)
                    }
                    if preferences.pageStatus.wrappedValue != "none" {
                        HStack {
                            Text("字号")
                            Slider(value: preferences.chromeFontSize, in: 9...15, step: 0.5)
                            Text(String(format: "%.1f", preferences.chromeFontSize.wrappedValue))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("浓度")
                            Slider(value: preferences.chromeOpacity, in: 0.35...1.0, step: 0.05)
                            Text("\(Int((preferences.chromeOpacity.wrappedValue * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("章节") {
                    Button("上一话") { runChapterAction(chapter.previous) }
                        .disabled(chapter.previous == nil)
                    Button("下一话") { runChapterAction(chapter.next) }
                        .disabled(chapter.next == nil)
                    if let download = chapter.download {
                        Button(chapter.isDownloading ? "停止漫画下载" : "下载本话供离线阅读", action: download)
                    }
                }
            }
            .navigationTitle("漫画设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("comic.settings.done")
                }
            }
            .navigationDestination(for: Route.self) { _ in readingModePicker }
        }
        .presentationDragIndicator(.visible)
    }

    private var readingModePicker: some View {
        List(ComicReadingMode.allCases) { mode in
            Button {
                preferences.mode.wrappedValue = mode
                path.removeLast()
            } label: {
                HStack {
                    Label(mode.rawValue, systemImage: mode.systemImage)
                    Spacer()
                    if preferences.mode.wrappedValue == mode { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            .accessibilityAddTraits(preferences.mode.wrappedValue == mode ? .isSelected : [])
        }
        .navigationTitle("阅读模式")
    }

    private func slotPicker(_ label: String, selection: Binding<String>) -> some View {
        Picker(label, selection: selection) {
            ForEach(ComicChromeSlotContent.allCases) { option in
                Text(option.title).tag(option.rawValue)
            }
        }
    }

    private func runChapterAction(_ action: (() -> Void)?) {
        guard let action else { return }
        dismiss()
        action()
    }
}
