import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("settings.themeMode") private var themeModeRawValue = ThemeMode.system.rawValue
    @AppStorage("settings.visualTheme") private var visualTheme = AppVisualTheme.classic.rawValue
    @AppStorage("settings.appearanceRevision") private var appearanceRevision = 0
    @AppStorage("settings.reducesMotion") private var reducesMotion = false
    @AppStorage("settings.readingDeskEnabled") private var readingDeskEnabled = true

    var body: some View {
        Form {
            Section {
                ForEach(AppVisualTheme.allCases) { theme in
                    Button { visualTheme = theme.rawValue } label: {
                        AppThemePreview(theme: theme, selected: visualTheme == theme.rawValue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(visualTheme == theme.rawValue ? [.isSelected] : [])
                    .listRowBackground(AppThemeRowSurface())
                }
            } header: { Text("全局主题") } footer: {
                Text("主题同时调整背景、卡片纸色、圆角、边框、默认字形与装饰，登录中心、规则体检和二级页面同步；不覆盖阅读背景或网页原始内容。每套主题的自定义配色独立保存。")
                Text(AppThemeSurfaceStyle.nativeGlassAvailable
                     ? "当前系统支持原生玻璃；浮动控件按需使用，滚动卡片保留主题纸面，避免叠加实时模糊。"
                     : "当前系统使用兼容材质；滚动卡片使用主题纸面，减少透明度或增强对比度时不叠加实时模糊。")
            }
            .listRowBackground(AppThemeRowSurface())
            Section {
                Toggle("空间书桌与藏书档案", isOn: $readingDeskEnabled)
                Text("关闭后使用经典紧凑展示。书籍、阅读位置、主题和系统导航保持不变。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("书籍展示") }
            .listRowBackground(AppThemeRowSurface())
            Section {
                Toggle("减少 App 动态效果", isOn: $reducesMotion)
                Text("同时尊重系统的“减弱动态效果”。关闭空间缩放和弹性反馈，不改变阅读进度或系统返回手势。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("统一动效") }
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
            .foregroundStyle(theme.dynamicColor(light: theme.accentHex, dark: theme.darkAccentHex))
            .frame(width: 56, height: 56)
            .background(theme.dynamicColor(light: theme.backgroundHex, dark: theme.darkBackgroundHex),
                        in: RoundedRectangle(cornerRadius: min(theme.radius, 14)))
            .overlay { AppThemeOrnament(theme: theme, isCard: true) }
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
