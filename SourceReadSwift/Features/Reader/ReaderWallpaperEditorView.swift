import SwiftUI

struct ReaderWallpaperDraft: Identifiable {
    let id = UUID()
    let image: UIImage
    var adjustment: ReaderWallpaperAdjustment
    var viewportSize = ReaderPerformancePolicy.defaultViewportSize
}

struct ReaderWallpaperEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let draft: ReaderWallpaperDraft
    let onApply: () -> Void
    @State private var adjustment: ReaderWallpaperAdjustment
    @State private var isSaving = false
    @State private var message: String?
    @State private var isNightPreview = false
    @State private var dragOrigin: CGPoint?

    init(draft: ReaderWallpaperDraft, onApply: @escaping () -> Void) {
        self.draft = draft; self.onApply = onApply
        _adjustment = State(initialValue: draft.adjustment)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("实时阅读预览 · 拖动调整位置") {
                    GeometryReader { geometry in
                        let previewSize = ReaderWallpaperLayoutPolicy.previewSize(viewport: draft.viewportSize, available: geometry.size)
                        let previewLightText = isNightPreview || adjustment.usesLightText
                        let inkColor: Color = {
                            if isNightPreview, let hex = adjustment.linkedNightInkHex { return Color(hex: hex) }
                            if !isNightPreview, let hex = adjustment.linkedInkHex { return Color(hex: hex) }
                            return previewLightText ? Color.white : Color.black
                        }()
                        let accentColor = adjustment.linkedAccentHex.map { Color(hex: $0) } ?? AppTheme.accent
                        ZStack(alignment: .topLeading) {
                            AppTheme.background
                            ReaderWallpaperView(
                                image: draft.image,
                                fillMode: adjustment.fillMode,
                                adjustment: adjustment,
                                isNight: isNightPreview
                            )
                            (previewLightText ? Color.black : Color.white)
                                .opacity(previewLightText ? (isNightPreview ? 0.25 : 0.20) : 0.14)
                            VStack(alignment: .leading, spacing: 12) {
                                Text("第二章 · 小岛来信")
                                    .font(.headline)
                                    .foregroundStyle(accentColor)
                                Text("风吹动纸页，云朵慢慢经过。\n\n文字要清楚，背景与主题色联动才会恰到好处。\n\n这是编辑预览，不会改变阅读进度。")
                                    .font(.caption).lineSpacing(6)
                                    .foregroundStyle(inkColor)
                            }.padding(20)
                        }
                        .frame(width: previewSize.width, height: previewSize.height)
                        .clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                        .gesture(DragGesture().onChanged { gesture in
                            if dragOrigin == nil { dragOrigin = CGPoint(x: adjustment.horizontalOffset, y: adjustment.verticalOffset) }
                            adjustment.horizontalOffset = min(max(Double(dragOrigin?.x ?? 0) + Double(gesture.translation.width / max(previewSize.width, 1)), -1), 1)
                            adjustment.verticalOffset = min(max(Double(dragOrigin?.y ?? 0) + Double(gesture.translation.height / max(previewSize.height, 1)), -1), 1)
                        }.onEnded { _ in dragOrigin = nil })
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }.frame(height: 320)
                    Toggle("夜间模式联动预览", isOn: $isNightPreview)
                }.listRowBackground(AppThemeRowSurface())
                Section("裁切、柔化与纸感") {
                    Picker("填充方式", selection: $adjustment.fillMode) {
                        ForEach(ReaderWallpaperFillMode.allCases) { Text($0.title).tag($0) }
                    }
                    slider("放大", value: $adjustment.zoom, range: 1...3)
                    slider("水平位置", value: $adjustment.horizontalOffset, range: -1...1)
                    slider("垂直位置", value: $adjustment.verticalOffset, range: -1...1)
                    slider("日间压暗", value: $adjustment.dimming, range: 0...0.6)
                    slider("夜间自动压暗", value: $adjustment.nightDimming, range: 0...0.85)
                    slider("背景柔化模糊", value: $adjustment.blurRadius, range: 0...24)
                    slider("宣纸颗粒质感", value: $adjustment.grainOpacity, range: 0...0.35)
                    Text("位置只移动超出边界的部分。柔化与压暗分别作用于日间与夜间阅读；取消不会覆盖原壁纸。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("重置裁切与滤镜") {
                        adjustment.zoom = 1
                        adjustment.horizontalOffset = 0
                        adjustment.verticalOffset = 0
                        adjustment.dimming = 0
                        adjustment.blurRadius = 0
                        adjustment.grainOpacity = 0
                        adjustment.nightDimming = 0.45
                    }
                }.listRowBackground(AppThemeRowSurface())
                Section("全链路色彩联动") {
                    Toggle("日间使用浅色文字", isOn: $adjustment.usesLightText)
                    Button {
                        extractHarmoniousPalette()
                    } label: {
                        HStack {
                            Label("一键从壁纸提取和谐配色", systemImage: "eyedropper.halffull")
                            Spacer()
                            if let accent = adjustment.linkedAccentHex, let dayInk = adjustment.linkedInkHex {
                                HStack(spacing: 4) {
                                    Circle().fill(Color(hex: accent)).frame(width: 14, height: 14)
                                    Circle().fill(Color(hex: dayInk)).frame(width: 14, height: 14)
                                }
                            }
                        }
                    }
                    if adjustment.linkedAccentHex != nil {
                        Button("清除联动取色，恢复默认黑白墨色", role: .destructive) {
                            adjustment.linkedInkHex = nil
                            adjustment.linkedNightInkHex = nil
                            adjustment.linkedAccentHex = nil
                            adjustment.linkedHeaderHex = nil
                        }
                        .font(.caption)
                    }
                }.listRowBackground(AppThemeRowSurface())
                if let message { Section { Text(message).foregroundStyle(.secondary).accessibilityLabel(message) }.listRowBackground(AppThemeRowSurface()) }
            }
            .disabled(isSaving).pageBackground().navigationTitle("编辑阅读壁纸").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) { Button(isSaving ? "保存中…" : "应用壁纸") { save() }.disabled(isSaving) }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func extractHarmoniousPalette() {
        let palette = CustomThemePaletteExtractor.extract(from: draft.image)
        if adjustment.usesLightText {
            adjustment.linkedInkHex = 0xF5F1E9
            adjustment.linkedAccentHex = palette.darkAccentHex
            adjustment.linkedHeaderHex = palette.darkSecondaryHex
        } else {
            adjustment.linkedInkHex = 0x1D2228
            adjustment.linkedAccentHex = palette.lightAccentHex
            adjustment.linkedHeaderHex = palette.lightSecondaryHex
        }
        adjustment.linkedNightInkHex = 0xE6E4DF
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline)
            Slider(value: value, in: range).accessibilityLabel(title)
        }
    }
    private func save() {
        guard !isSaving else { return }
        isSaving = true; message = nil
        Task { @MainActor in
            do {
                try await ReaderCustomWallpaperStore.saveEditedWallpaper(draft.image, adjustment: adjustment)
                onApply(); dismiss()
            } catch { message = "保存壁纸失败，原设置未替换。" + error.localizedDescription }
            isSaving = false
        }
    }
}
