import SwiftUI

/// Keep the existing preference keys so upgrading does not reset a theme.
struct AppearanceSettingsView: View {
    @AppStorage("settings.themeMode") private var themeModeRawValue = ThemeMode.system.rawValue
    @AppStorage("settings.accentHex") private var accentHex = "594FDB"
    @AppStorage("settings.secondaryAccentHex") private var secondaryAccentHex = "419BDC"

    var body: some View {
        Form {
            Section("显示模式") {
                ForEach(ThemeMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            themeModeRawValue = mode.rawValue
                        }
                    } label: {
                        HStack {
                            Text(mode.title).foregroundStyle(.primary)
                            Spacer()
                            if (ThemeMode(rawValue: themeModeRawValue) ?? .system) == mode {
                                Image(systemName: "checkmark").foregroundStyle(AppTheme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(themeModeRawValue == mode.rawValue ? [.isSelected] : [])
                }
            }
            Section {
                ColorPicker("主题主色", selection: Binding(
                    get: { AppTheme.accent },
                    set: { if let hex = AppTheme.hex($0) { accentHex = hex } }
                ), supportsOpacity: false)
                ColorPicker("主题辅色", selection: Binding(
                    get: { AppTheme.secondaryAccent },
                    set: { if let hex = AppTheme.hex($0) { secondaryAccentHex = hex } }
                ), supportsOpacity: false)
                HStack(spacing: 8) {
                    ForEach(["594FDB", "267A62", "B75473", "B76A2C", "3476B8"], id: \.self) { hex in
                        Button { accentHex = hex } label: {
                            Circle()
                                .fill(presetColor(hex))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(.primary.opacity(accentHex == hex ? 0.8 : 0), lineWidth: 2))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("主题色 \(hex)")
                    }
                }
                Button("恢复纸间默认配色") {
                    accentHex = "594FDB"
                    secondaryAccentHex = "419BDC"
                }
            } header: {
                Text("主题配色")
            } footer: {
                Text("只调整应用界面配色，不覆盖书籍的阅读背景和字体颜色。")
            }
        }
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppTheme.accent)
    }

    private func presetColor(_ hex: String) -> Color {
        let rgb = UInt32(hex, radix: 16) ?? 0x594FDB
        return Color(red: Double((rgb >> 16) & 255) / 255,
                     green: Double((rgb >> 8) & 255) / 255,
                     blue: Double(rgb & 255) / 255)
    }
}
