import SwiftUI

struct ReaderWallpaperDraft: Identifiable {
    let id = UUID()
    let image: UIImage
    var adjustment: ReaderWallpaperAdjustment
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
                        ZStack(alignment: .topLeading) {
                            AppTheme.background
                            ReaderWallpaperView(image: draft.image, fillMode: adjustment.fillMode, adjustment: adjustment)
                            (adjustment.usesLightText ? Color.black : Color.white)
                                .opacity(adjustment.usesLightText ? (isNightPreview ? 0.60 : 0.35) : (isNightPreview ? 0.15 : 0.20))
                            VStack(alignment: .leading, spacing: 12) {
                                Text("第二章 · 小岛来信").font(.headline)
                                Text("风吹动纸页，云朵慢慢经过。\n\n文字要清楚，背景才会恰到好处。\n\n这是编辑预览，不会改变阅读进度。")
                                    .font(.body).lineSpacing(6)
                            }.foregroundStyle(adjustment.usesLightText ? Color.white : Color.black).padding(20)
                        }
                        .clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                        .gesture(DragGesture().onChanged { gesture in
                            if dragOrigin == nil { dragOrigin = CGPoint(x: adjustment.horizontalOffset, y: adjustment.verticalOffset) }
                            adjustment.horizontalOffset = min(max(Double(dragOrigin?.x ?? 0) + Double(gesture.translation.width / max(geometry.size.width, 1)), -1), 1)
                            adjustment.verticalOffset = min(max(Double(dragOrigin?.y ?? 0) + Double(gesture.translation.height / max(geometry.size.height, 1)), -1), 1)
                        }.onEnded { _ in dragOrigin = nil })
                    }.frame(height: 320)
                    Toggle("夜间遮罩预览", isOn: $isNightPreview)
                }.listRowBackground(AppThemeRowSurface())
                Section("裁切与可读性") {
                    Picker("填充方式", selection: $adjustment.fillMode) {
                        ForEach(ReaderWallpaperFillMode.allCases) { Text($0.title).tag($0) }
                    }
                    slider("放大", value: $adjustment.zoom, range: 1...3)
                    slider("水平位置", value: $adjustment.horizontalOffset, range: -1...1)
                    slider("垂直位置", value: $adjustment.verticalOffset, range: -1...1)
                    slider("压暗图片", value: $adjustment.dimming, range: 0...0.6)
                    Toggle("使用浅色文字", isOn: $adjustment.usesLightText)
                    Text("位置只移动超出边界的部分。预览使用与阅读页相同的填充、裁切与遮罩；取消不会覆盖原壁纸。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("重置裁切") {
                        adjustment.zoom = 1; adjustment.horizontalOffset = 0; adjustment.verticalOffset = 0; adjustment.dimming = 0
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
