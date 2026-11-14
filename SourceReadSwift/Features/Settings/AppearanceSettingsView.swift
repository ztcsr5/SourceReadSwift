import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("settings.themeMode") private var themeModeRawValue = ThemeMode.system.rawValue
    @AppStorage(AppVisualTheme.selectionKey) private var visualTheme = AppVisualTheme.initialSelection.rawValue
    @AppStorage("settings.appearanceRevision") private var appearanceRevision = 0
    @AppStorage("settings.readingDeskEnabled") private var readingDeskEnabled = true
    @AppStorage(HomeCompositionPreference.storageKey) private var homeCompositionRaw = HomeCompositionPreference.autoRawValue
    @ObservedObject private var customStore = AppCustomThemeStore.shared
    @ObservedObject private var iconManager = AppIconManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var pendingIconSync: AppIconOption?

    var body: some View {
        Form {
            Section {
                themeRows(AppVisualTheme.whitelistedCoreThemes)
            } header: { Text("核心纸间主题") } footer: {
                Text("四套常驻主题。森林绿保留纯白纸面。")
            }

            Section("氛围主题") {
                NavigationLink {
                    AtmosphericThemeGallery(appliedThemeRaw: $visualTheme,
                                            isDark: colorScheme == .dark, onApply: selectTheme)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "book.pages").foregroundStyle(AppTheme.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("主题画册").font(.headline)
                            Text("墨山、竹雨、晴空、花信")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .accessibilityIdentifier("appearance.atmosphere.gallery")
                .listRowBackground(AppThemeRowSurface())
            }

            Section {
                Button {
                    visualTheme = AppVisualTheme.custom.rawValue
                    appearanceRevision += 1
                } label: {
                    AppThemePreview(theme: .custom, selected: visualTheme == AppVisualTheme.custom.rawValue)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("app.theme.custom")
                .accessibilityAddTraits(visualTheme == AppVisualTheme.custom.rawValue ? [.isSelected] : [])
                .listRowBackground(AppThemeRowSurface())

                NavigationLink {
                    CustomThemeWorkshopView()
                } label: {
                    HStack {
                        Label("打开自定义主题工坊", systemImage: "paintpalette")
                        Spacer()
                        Text(customStore.activePreset.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(AppThemeRowSurface())
            } header: { Text("自定义工坊 · 多方案") } footer: {
                Text("支持相册选图 / 渐变 / 纯色背景、模糊与压暗、从图片一键提取和谐主色、圆角与全局字体定制。")
            }

            Section {
                Picker("首页与书架排版", selection: $homeCompositionRaw) {
                    Text("跟随主题推荐").tag(HomeCompositionPreference.autoRawValue)
                    ForEach(AppVisualTheme.HomeComposition.allCases) { composition in
                        Text(composition.title).tag(composition.rawValue)
                    }
                }
                .listRowBackground(AppThemeRowSurface())

                Toggle("空间书桌与藏书档案", isOn: $readingDeskEnabled)
                    .listRowBackground(AppThemeRowSurface())
                Text("布局与视觉主题完全解耦，可任意混搭；关闭空间书桌后切换为紧凑卡片展示。")
                    .font(.caption).foregroundStyle(.secondary)
                    .listRowBackground(AppThemeRowSurface())
            } header: { Text("首页布局与陈列") }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(AppIconOption.allCases) { option in
                            iconChoiceTile(option)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(AppThemeRowSurface())
                if let option = pendingIconSync {
                    HStack(spacing: 10) {
                        Text("可同步为「\(option.title)」配套图标")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("同步图标") {
                            Task { await iconManager.select(option) }
                            pendingIconSync = nil
                        }
                        .font(.caption.weight(.medium))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .disabled(iconManager.isSelecting)
                        Button("暂不") {
                            pendingIconSync = nil
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                    .listRowBackground(AppThemeRowSurface())
                }
                if iconManager.isSelecting {
                    Text("正在同步图标…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(AppThemeRowSurface())
                } else if let status = iconManager.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(AppThemeRowSurface())
                }
            } header: { Text("桌面图标") } footer: {
                Text("iOS 只允许切换 App 随包提供的桌面图标。若未启用自定义徽标，App 内也使用所选图标。")
            }

            Section {
                NavigationLink {
                    PersonalBrandMarkSettings()
                } label: {
                    Label("相册自定义徽标", systemImage: "photo.badge.plus")
                }
                .accessibilityIdentifier("appearance.personalBrand")
                .listRowBackground(AppThemeRowSurface())
            } header: {
                Text("App 内徽标")
            }

            Section("显示模式（全链路日 / 夜）") {
                Picker("明暗", selection: Binding(
                    get: {
                        let parsed = ThemeMode(rawValue: themeModeRawValue) ?? .system
                        return parsed == .eyeCare ? ThemeMode.light.rawValue : parsed.rawValue
                    },
                    set: { themeModeRawValue = $0 }
                )) {
                    ForEach(ThemeMode.pickerCases) { mode in Text(mode.title).tag(mode.rawValue) }
                }
            }
            .listRowBackground(AppThemeRowSurface())

            Section {
                ColorPicker("主题主色", selection: colorBinding("accent"), supportsOpacity: false)
                ColorPicker("主题辅色", selection: colorBinding("secondaryAccent"), supportsOpacity: false)
                Button("恢复当前主题默认配色") {
                    for component in ["accent", "secondaryAccent"] {
                        let key = AppVisualTheme.current.preferenceKey(component)
                        UserDefaults.standard.removeObject(forKey: key)
                        UserDefaults.standard.removeObject(forKey: key + ".dark")
                    }
                    appearanceRevision += 1
                }
            } header: { Text("当前主题 · 微调配色") }
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
            Button {
                selectTheme(theme)
            } label: {
                AppThemePreview(theme: theme, selected: visualTheme == theme.rawValue)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("app.theme." + theme.rawValue)
            .accessibilityAddTraits(visualTheme == theme.rawValue ? [.isSelected] : [])
            .listRowBackground(AppThemeRowSurface())
        }
    }

    private func selectTheme(_ theme: AppVisualTheme) {
        guard visualTheme != theme.rawValue else { return }
        visualTheme = theme.rawValue
        let recommended = AppIconOption.recommended(for: theme)
        pendingIconSync = iconManager.currentOption == recommended ? nil : recommended
    }

    private func iconChoiceTile(_ option: AppIconOption) -> some View {
        let isSelected = iconManager.currentOption == option
        return Button {
            Task { await iconManager.select(option) }
        } label: {
            VStack(spacing: 6) {
                Image(option.brandMarkAssetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(isSelected ? AppTheme.accent : .primary.opacity(0.12),
                                    lineWidth: isSelected ? 2.5 : 0.75)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(AppTheme.accent)
                                .background(Circle().fill(AppTheme.card))
                                .offset(x: 4, y: -4)
                        }
                    }
                Text(option.title)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AppTheme.accent : .primary)
                    .lineLimit(1)
            }
            .frame(width: 72)
        }
        .buttonStyle(AppPressStyle())
        .disabled(iconManager.isSelecting)
        .accessibilityIdentifier("app.icon." + option.rawValue)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func colorBinding(_ component: String) -> Binding<Color> {
        let storageSuffix = colorScheme == .dark ? ".dark" : ""
        return Binding(get: {
            _ = appearanceRevision
            return component == "accent" ? AppTheme.accent : AppTheme.secondaryAccent
        }, set: {
            if let hex = AppTheme.hex($0) {
                UserDefaults.standard.set(hex, forKey: AppVisualTheme.current.preferenceKey(component) + storageSuffix)
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
            previewBadge
                .frame(width: 56, height: 56)
                .background(
                    theme.dynamicColor(light: theme.backgroundHex, dark: theme.darkBackgroundHex),
                    in: RoundedRectangle(cornerRadius: min(theme.radius, 14), style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: min(theme.radius, 14), style: .continuous)
                        .stroke(.primary.opacity(theme.usesNeutralGlass ? 0.08 : 0.14), lineWidth: 0.75)
                }
                .overlay { AppThemeOrnament(theme: theme, isCard: true) }

            VStack(alignment: .leading, spacing: 4) {
                Text(theme.title)
                    .font(theme.titleFont(size: 16, weight: .semibold))
                Text(theme.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var previewBadge: some View {
        if let asset = theme.atmosphericPaperAsset(isDark: false) {
            Image(asset)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: min(theme.radius, 14), style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(theme.dynamicColor(light: theme.accentHex, dark: theme.darkAccentHex))
                        .frame(width: 10, height: 10)
                        .padding(5)
                }
        } else {
            HStack(spacing: 4) {
                if theme.homeComposition != .editorial { previewTile(width: 14, height: 26) }
                VStack(alignment: .leading, spacing: 4) {
                    previewTile(width: 18, height: 3)
                    previewTile(width: 13, height: 3)
                }
                if theme.homeComposition == .editorial { previewTile(width: 14, height: 26) }
            }
            .foregroundStyle(theme.dynamicColor(light: theme.accentHex, dark: theme.darkAccentHex))
        }
    }

    private func previewTile(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: min(theme.radius / 6, 3))
            .fill(theme.dynamicColor(light: theme.accentHex, dark: theme.darkAccentHex).opacity(0.68))
            .frame(width: width, height: height)
    }
}
