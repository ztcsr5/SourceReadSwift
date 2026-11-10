import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("settings.themeMode") private var themeModeRawValue = ThemeMode.system.rawValue
    @AppStorage(AppVisualTheme.selectionKey) private var visualTheme = AppVisualTheme.initialSelection.rawValue
    @AppStorage("settings.appearanceRevision") private var appearanceRevision = 0
    @AppStorage("settings.readingDeskEnabled") private var readingDeskEnabled = true

    var body: some View {
        Form {
            Section {
                themeRows(AppVisualTheme.classicDeskThemes.filter { !$0.isAtelier })
            } header: { Text("经典书台") } footer: {
                Text("主题同时切换首页编排、书架陈列、页面纸面和控件边框。原初白紫保留现有书台；书刊、索引和藏书票各有独立布局。")
            }
            Section {
                themeRows(AppVisualTheme.floatingBookThemes)
            } header: { Text("悬浮书籍") } footer: {
                Text("森林绿保持纯白。竹影、潮汐、银杏与远山使用独立插画背景，不会覆盖正文的阅读壁纸。")
                Text(AppThemeSurfaceStyle.nativeGlassAvailable
                     ? "当前系统支持原生玻璃；浮动控件按需使用，滚动卡片保留主题纸面，避免叠加实时模糊。"
                     : "当前系统使用兼容材质；滚动卡片使用主题纸面，减少透明度或增强对比度时不叠加实时模糊。")
            }
            .listRowBackground(AppThemeRowSurface())
            Section {
                themeRows(AppVisualTheme.atelierThemes)
            } header: { Text("色彩沙龙") } footer: {
                Text("七组双色搭配，同时改变纸面、卡片轮廓、边缘装饰、阅读卡和书架编排。明暗模式分别调色，保留你已保存的阅读背景。")
            }
            Section {
                Toggle("空间书桌与藏书档案", isOn: $readingDeskEnabled)
                Text("关闭后使用经典紧凑展示。书籍、阅读位置、主题和系统导航保持不变。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("书籍展示") }
            .listRowBackground(AppThemeRowSurface())
            Section("显示模式") {
                Picker("明暗", selection: $themeModeRawValue) {
                    ForEach(ThemeMode.allCases) { mode in Text(mode.title).tag(mode.rawValue) }
                }
            }
            .listRowBackground(AppThemeRowSurface())
            Section {
                ColorPicker("主题主色", selection: colorBinding("accent"), supportsOpacity: false)
                ColorPicker("主题辅色", selection: colorBinding("secondaryAccent"), supportsOpacity: false)
                Button("恢复当前主题配色") {
                    for component in ["accent", "secondaryAccent"] {
                        UserDefaults.standard.removeObject(forKey: AppVisualTheme.current.preferenceKey(component))
                    }
                    appearanceRevision += 1
                }
            } header: { Text("当前主题 · 自定义配色") }
            .listRowBackground(AppThemeRowSurface())
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppTheme.accent)
    }

    private func themeRows(_ themes: [AppVisualTheme]) -> some View {
        ForEach(themes) { theme in
            Button { visualTheme = theme.rawValue } label: {
                AppThemePreview(theme: theme, selected: visualTheme == theme.rawValue)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("app.theme." + theme.rawValue)
            .accessibilityAddTraits(visualTheme == theme.rawValue ? [.isSelected] : [])
            .listRowBackground(AppThemeRowSurface())
        }
    }

    private func colorBinding(_ component: String) -> Binding<Color> {
        Binding(get: {
            _ = appearanceRevision
            return component == "accent" ? AppTheme.accent : AppTheme.secondaryAccent
        }, set: {
            if let hex = AppTheme.hex($0) {
                UserDefaults.standard.set(hex, forKey: AppVisualTheme.current.preferenceKey(component))
                appearanceRevision += 1
            }
        })
    }
}

struct AppThemePreview: View {
    let theme: AppVisualTheme
    var selected = false
    var body: some View {
        HStack(spacing: 12) {
            compositionPreview
            .foregroundStyle(theme.dynamicColor(light: theme.accentHex, dark: theme.darkAccentHex))
            .frame(width: 56, height: 56)
            .overlay(alignment: .bottom) {
                if let palette = theme.atelierPalette {
                    HStack(spacing: 0) {
                        Rectangle().fill(palette.primary)
                        Rectangle().fill(palette.secondary)
                    }
                    .frame(width: 36, height: 5)
                    .padding(.bottom, 4)
                    .accessibilityHidden(true)
                }
            }
            .background(theme.dynamicColor(light: theme.backgroundHex, dark: theme.darkBackgroundHex),
                        in: RoundedRectangle(cornerRadius: min(theme.radius, 14)))
            .overlay { AppThemeOrnament(theme: theme, isCard: true) }
            VStack(alignment: .leading, spacing: 4) {
                Text(theme.title).font(.system(.subheadline, design: theme.fontDesign).weight(.semibold))
                Text(theme.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(theme.compositionTitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.accent) }
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var compositionPreview: some View {
        if theme.isAtelier {
            HStack(spacing: 4) {
                if theme.homeComposition != .editorial { previewTile(width: 14, height: 26) }
                VStack(alignment: .leading, spacing: 4) {
                    previewTile(width: 18, height: 3)
                    previewTile(width: 13, height: 3)
                    previewTile(width: 16, height: 2)
                }
                if theme.homeComposition == .editorial { previewTile(width: 14, height: 26) }
            }
        } else {
            legacyCompositionPreview
        }
    }

    @ViewBuilder private var legacyCompositionPreview: some View {
        switch theme.homeComposition {
        case .readingDesk:
            HStack(spacing: 4) {
                previewTile(width: 14, height: 26)
                VStack(alignment: .leading, spacing: 4) {
                    previewTile(width: 18, height: 3)
                    previewTile(width: 13, height: 3)
                }
            }
        case .editorial:
            VStack(alignment: .leading, spacing: 4) {
                previewTile(width: 35, height: 3)
                HStack(spacing: 4) { previewTile(width: 17, height: 21); previewTile(width: 13, height: 21) }
            }
        case .index:
            VStack(spacing: 4) {
                ForEach(0..<3) { _ in
                    HStack(spacing: 4) { previewTile(width: 6, height: 6); previewTile(width: 25, height: 3) }
                }
            }
        case .gallery:
            HStack(spacing: 5) { previewTile(width: 15, height: 27); previewTile(width: 15, height: 27) }
        }
    }

    private func previewTile(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: min(theme.radius / 6, 3))
            .fill(theme.dynamicColor(light: theme.accentHex, dark: theme.darkAccentHex).opacity(0.65))
            .frame(width: width, height: height)
    }
}
