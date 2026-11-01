import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("settings.themeMode") private var themeModeRawValue = ThemeMode.system.rawValue
    @AppStorage("settings.visualTheme") private var visualTheme = AppVisualTheme.classic.rawValue
    @AppStorage("settings.appearanceRevision") private var appearanceRevision = 0

    var body: some View {
        Form {
            Section {
                ForEach(AppVisualTheme.allCases) { theme in
                    Button { visualTheme = theme.rawValue } label: {
                        AppThemePreview(theme: theme, selected: visualTheme == theme.rawValue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(visualTheme == theme.rawValue ? [.isSelected] : [])
                    .listRowBackground(AppTheme.card)
                }
            } header: { Text("全局主题") } footer: {
                Text("主题同时调整背景、卡片纸色、圆角、边框、默认字形与装饰；不替换主页布局，不覆盖阅读背景。每套主题的自定义配色独立保存。")
            }
            Section("显示模式") {
                Picker("明暗", selection: $themeModeRawValue) {
                    ForEach(ThemeMode.allCases) { mode in Text(mode.title).tag(mode.rawValue) }
                }
            }
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
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppTheme.accent)
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
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: theme.ornament).font(.system(size: 15))
                RoundedRectangle(cornerRadius: theme.radius / 6)
                    .fill(theme.dynamicColor(light: theme.cardHex, dark: theme.darkCardHex))
                    .overlay(RoundedRectangle(cornerRadius: theme.radius / 6)
                        .stroke(.primary.opacity(0.18), lineWidth: theme.borderWidth))
                    .frame(width: 35, height: 15)
            }
            .foregroundStyle(Color(uiColor: AppVisualTheme.uiColor(theme.accentHex)))
            .frame(width: 56, height: 56)
            .background(theme.dynamicColor(light: theme.backgroundHex, dark: theme.darkBackgroundHex),
                        in: RoundedRectangle(cornerRadius: min(theme.radius, 14)))
            VStack(alignment: .leading, spacing: 4) {
                Text(theme.title).font(.system(.subheadline, design: theme.fontDesign).weight(.semibold))
                Text(theme.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.accent) }
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(Rectangle())
    }
}
