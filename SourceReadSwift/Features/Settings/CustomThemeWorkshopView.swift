import PhotosUI
import SwiftUI
import UIKit

struct CustomThemeWorkshopView: View {
    @ObservedObject private var store = AppCustomThemeStore.shared
    @AppStorage(AppVisualTheme.selectionKey) private var visualTheme = AppVisualTheme.initialSelection.rawValue
    @AppStorage("settings.appearanceRevision") private var appearanceRevision = 0
    @State private var previewDarkMode = false
    @State private var lightPickerItem: PhotosPickerItem?
    @State private var darkPickerItem: PhotosPickerItem?
    @State private var showingNewPresetPrompt = false
    @State private var newPresetName = ""
    @State private var paletteMessage: String?

    private var preset: CustomThemePreset { store.activePreset }

    var body: some View {
        Form {
            presetSection
            previewSection
            backdropSection
            colorSection
            geometryAndFontSection
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("自定义主题工坊")
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppTheme.accent)
        .onChange(of: lightPickerItem) { item in
            guard let item else { return }
            Task { await handlePickedPhoto(item: item, isDarkVariant: false) }
        }
        .onChange(of: darkPickerItem) { item in
            guard let item else { return }
            Task { await handlePickedPhoto(item: item, isDarkVariant: true) }
        }
        .alert("新建主题方案", isPresented: $showingNewPresetPrompt) {
            TextField("方案名称", text: $newPresetName)
            Button("创建") {
                _ = store.createPreset(name: newPresetName, cloningCurrent: false)
                newPresetName = ""
                visualTheme = AppVisualTheme.custom.rawValue
            }
            Button("取消", role: .cancel) { newPresetName = "" }
        }
    }

    private var presetSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.presets) { item in
                        Button {
                            store.selectPreset(item.id)
                            visualTheme = AppVisualTheme.custom.rawValue
                        } label: {
                            Text(item.name)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    item.id == preset.id ? AppTheme.accent : AppTheme.card,
                                    in: Capsule()
                                )
                                .foregroundStyle(item.id == preset.id ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        newPresetName = "方案 \(store.presets.count + 1)"
                        showingNewPresetPrompt = true
                    } label: {
                        Label("新建", systemImage: "plus")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(AppTheme.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
            TextField("当前方案名称", text: Binding(
                get: { preset.name },
                set: { val in store.updateActive { $0.name = val } }
            ))
            HStack {
                Button(visualTheme == AppVisualTheme.custom.rawValue ? "当前已应用此自定义主题" : "设为当前应用主题") {
                    visualTheme = AppVisualTheme.custom.rawValue
                    appearanceRevision += 1
                }
                .font(.subheadline.weight(.medium))
                Spacer()
                if store.presets.count > 1 {
                    Button("删除此方案", role: .destructive) {
                        store.deletePreset(preset.id)
                    }
                    .font(.caption)
                }
            }
        } header: { Text("多方案管理") }
        .listRowBackground(AppThemeRowSurface())
    }

    private var previewSection: some View {
        Section {
            VStack(spacing: 10) {
                HStack {
                    Text("效果预览").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker("预览明暗", selection: $previewDarkMode) {
                        Text("日间").tag(false)
                        Text("深色").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
                CustomThemeMiniPreview(preset: preset, isDark: previewDarkMode)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(AppThemeRowSurface())
    }

    private var backdropSection: some View {
        Section {
            Picker("背景类型", selection: Binding(
                get: { preset.backdropKind },
                set: { kind in store.updateActive { $0.backdropKind = kind } }
            )) {
                ForEach(CustomThemeBackdropKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            switch preset.backdropKind {
            case .solid:
                ColorPicker("日间底色", selection: hexBinding(\.lightSolidHex), supportsOpacity: false)
                ColorPicker("深色底色", selection: hexBinding(\.darkSolidHex), supportsOpacity: false)
            case .gradient:
                ColorPicker("日间起点色", selection: hexBinding(\.gradientStartHex), supportsOpacity: false)
                ColorPicker("日间终点色", selection: hexBinding(\.gradientEndHex), supportsOpacity: false)
                ColorPicker("深色起点色", selection: hexBinding(\.darkGradientStartHex), supportsOpacity: false)
                ColorPicker("深色终点色", selection: hexBinding(\.darkGradientEndHex), supportsOpacity: false)
            case .photo:
                PhotosPicker(selection: $lightPickerItem, matching: .images) {
                    Label(preset.lightImageFilename == nil ? "从相册选择日间背景图" : "更换日间背景图", systemImage: "photo")
                }
                PhotosPicker(selection: $darkPickerItem, matching: .images) {
                    Label(preset.darkImageFilename == nil ? "单独选深色背景图（可选，默认自动压暗）" : "更换深色背景图", systemImage: "moon.stars")
                }
                if preset.darkImageFilename != nil {
                    Button("清除深色图（改用日间图自动压暗）", role: .destructive) {
                        store.updateActive { $0.darkImageFilename = nil }
                    }
                }
                if preset.lightImageFilename != nil || preset.darkImageFilename != nil {
                    Button {
                        Task { await applyExtractedPalette() }
                    } label: {
                        Label("从背景图一键提取和谐主色/辅色", systemImage: "wand.and.stars")
                    }
                    if let paletteMessage {
                        Text(paletteMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("模糊度 · \(Int(preset.blurRadius.rounded()))").font(.caption)
                    Slider(value: Binding(
                        get: { preset.blurRadius },
                        set: { val in store.updateActive { $0.blurRadius = val } }
                    ), in: 0...24, step: 2)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("日间压暗 · \(Int((preset.lightDimming * 100).rounded()))%").font(.caption)
                    Slider(value: Binding(
                        get: { preset.lightDimming },
                        set: { val in store.updateActive { $0.lightDimming = val } }
                    ), in: 0...0.65, step: 0.05)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("深色压暗 · \(Int((preset.darkDimming * 100).rounded()))%").font(.caption)
                    Slider(value: Binding(
                        get: { preset.darkDimming },
                        set: { val in store.updateActive { $0.darkDimming = val } }
                    ), in: 0.15...0.85, step: 0.05)
                }
            }
        } header: { Text("背景与质感") }
        .listRowBackground(AppThemeRowSurface())
    }

    private var colorSection: some View {
        Section {
            ColorPicker("日间主色", selection: hexBinding(\.lightAccentHex), supportsOpacity: false)
            ColorPicker("日间辅色", selection: hexBinding(\.lightSecondaryHex), supportsOpacity: false)
            ColorPicker("日间卡片色", selection: hexBinding(\.lightCardHex), supportsOpacity: false)
            ColorPicker("深色主色", selection: hexBinding(\.darkAccentHex), supportsOpacity: false)
            ColorPicker("深色辅色", selection: hexBinding(\.darkSecondaryHex), supportsOpacity: false)
            ColorPicker("深色卡片色", selection: hexBinding(\.darkCardHex), supportsOpacity: false)
        } header: { Text("日 / 夜双套配色") }
        .listRowBackground(AppThemeRowSurface())
    }

    private var geometryAndFontSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("卡片圆角 · \(Int(preset.cornerRadius.rounded())) pt").font(.caption)
                Slider(value: Binding(
                    get: { preset.cornerRadius },
                    set: { val in store.updateActive { $0.cornerRadius = val } }
                ), in: 4...28, step: 1)
            }
            Picker("卡片表面", selection: Binding(
                get: { preset.cardSurface },
                set: { val in store.updateActive { $0.cardSurface = val } }
            )) {
                ForEach(CustomThemeCardSurface.allCases) { surface in
                    Text(surface.title).tag(surface)
                }
            }
            .pickerStyle(.segmented)
            Picker("全局字体风格", selection: Binding(
                get: { preset.fontStyle },
                set: { val in store.updateActive { $0.fontStyle = val } }
            )) {
                ForEach(CustomThemeFontStyle.allCases) { font in
                    Text(font.title).tag(font)
                }
            }
        } header: { Text("圆角与字体") }
        .listRowBackground(AppThemeRowSurface())
    }

    private func hexBinding(_ keyPath: WritableKeyPath<CustomThemePreset, UInt32>) -> Binding<Color> {
        Binding(
            get: { Color(uiColor: AppVisualTheme.uiColor(preset[keyPath: keyPath])) },
            set: { newColor in
                if let hex = AppTheme.hex(newColor), let value = UInt32(hex, radix: 16) {
                    store.updateActive { $0[keyPath: keyPath] = value }
                }
            }
        )
    }

    private func handlePickedPhoto(item: PhotosPickerItem, isDarkVariant: Bool) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        _ = await store.saveBackgroundImage(data: data, isDarkVariant: isDarkVariant)
        visualTheme = AppVisualTheme.custom.rawValue
        if !isDarkVariant {
            await applyExtractedPalette()
        }
    }

    private func applyExtractedPalette() async {
        let filename = preset.lightImageFilename ?? preset.darkImageFilename
        guard let image = await AppCustomThemeStore.loadImage(filename: filename, blurRadius: 0) else { return }
        let extracted = await Task.detached(priority: .userInitiated) {
            CustomThemePaletteExtractor.extractHarmoniousPalette(from: image)
        }.value
        store.updateActive { target in
            target.lightAccentHex = extracted.lightAccentHex
            target.lightSecondaryHex = extracted.lightSecondaryHex
            target.lightBackgroundHex = extracted.lightBackgroundHex
            target.lightCardHex = extracted.lightCardHex
            target.darkAccentHex = extracted.darkAccentHex
            target.darkSecondaryHex = extracted.darkSecondaryHex
            target.darkBackgroundHex = extracted.darkBackgroundHex
            target.darkCardHex = extracted.darkCardHex
        }
        paletteMessage = "已根据背景主色调自动匹配对比度达标的日 / 夜配色。"
    }
}

private struct CustomThemeMiniPreview: View {
    let preset: CustomThemePreset
    let isDark: Bool
    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack {
            backdropView
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(preset.name)
                        .font(preset.fontStyle.displayFontName.map { .custom($0, size: 17) }
                            ?? .system(size: 17, design: preset.fontStyle.fontDesign))
                        .fontWeight(.semibold)
                        .foregroundStyle(isDark ? Color.white : Color.black)
                    Spacer()
                    Text(isDark ? "深色" : "日间")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(accentColor.opacity(0.20), in: Capsule())
                        .foregroundStyle(accentColor)
                }
                Text("字里行间 · 与背景和谐共生的高对比阅读卡片预览")
                    .font(.system(.caption, design: preset.fontStyle.fontDesign))
                    .foregroundStyle((isDark ? Color.white : Color.black).opacity(0.75))
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accentColor)
                        .frame(width: 28, height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(secondaryColor)
                        .frame(width: 18, height: 6)
                }
            }
            .padding(14)
            .background(
                preset.cardSurface == .glass ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(cardColor.opacity(preset.cardOpacity)),
                in: RoundedRectangle(cornerRadius: min(preset.cornerRadius, 24), style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: min(preset.cornerRadius, 24), style: .continuous)
                    .stroke((isDark ? Color.white : Color.black).opacity(0.08), lineWidth: 0.75)
            }
            .padding(14)
        }
        .task(id: "\(preset.lightImageFilename ?? "")-\(preset.darkImageFilename ?? "")-\(Int(preset.blurRadius))-\(isDark)") {
            let name = isDark ? (preset.darkImageFilename ?? preset.lightImageFilename) : preset.lightImageFilename
            loadedImage = await AppCustomThemeStore.loadImage(filename: name, blurRadius: preset.blurRadius)
        }
    }

    @ViewBuilder private var backdropView: some View {
        switch preset.backdropKind {
        case .solid:
            Color(uiColor: AppVisualTheme.uiColor(isDark ? preset.darkSolidHex : preset.lightSolidHex))
        case .gradient:
            LinearGradient(
                colors: [
                    Color(uiColor: AppVisualTheme.uiColor(isDark ? preset.darkGradientStartHex : preset.gradientStartHex)),
                    Color(uiColor: AppVisualTheme.uiColor(isDark ? preset.darkGradientEndHex : preset.gradientEndHex)),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .photo:
            ZStack {
                Color(uiColor: AppVisualTheme.uiColor(isDark ? preset.darkBackgroundHex : preset.lightBackgroundHex))
                if let loadedImage {
                    Image(uiImage: loadedImage).resizable().scaledToFill()
                }
                (isDark ? Color.black : Color.white)
                    .opacity(isDark ? preset.darkDimming : preset.lightDimming)
            }
        }
    }

    private var accentColor: Color {
        Color(uiColor: AppVisualTheme.uiColor(isDark ? preset.darkAccentHex : preset.lightAccentHex))
    }

    private var secondaryColor: Color {
        Color(uiColor: AppVisualTheme.uiColor(isDark ? preset.darkSecondaryHex : preset.lightSecondaryHex))
    }

    private var cardColor: Color {
        Color(uiColor: AppVisualTheme.uiColor(isDark ? preset.darkCardHex : preset.lightCardHex))
    }
}
