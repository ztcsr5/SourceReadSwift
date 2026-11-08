from pathlib import Path
R=Path(__file__).resolve().parents[2]
def edit(name, old, new):
 p=R/name;s=p.read_text(encoding='utf8');assert old in s,(name,old[:80]);p.write_text(s.replace(old,new,1),encoding='utf8')
edit('SourceReadSwift/Shared/DesignSystem/AppTheme.swift','    static let accent = Color(red: 0.35, green: 0.31, blue: 0.86)\n    static let accentUIColor = UIColor(red: 0.35, green: 0.31, blue: 0.86, alpha: 1)\n    static let softBlue = Color(red: 0.86, green: 0.92, blue: 1.0)', '''    static var accentUIColor: UIColor { color(for: "settings.accentHex", fallback: 0x594FDB) }
    static var accent: Color { Color(uiColor: accentUIColor) }
    static var secondaryAccent: Color { Color(uiColor: color(for: "settings.secondaryAccentHex", fallback: 0x419BDC)) }
    static var softBlue: Color { secondaryAccent.opacity(0.16) }

    static func color(for key: String, fallback: UInt32) -> UIColor {
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        let rgb = raw.count == 6 ? UInt32(raw, radix: 16) ?? fallback : fallback
        return UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                       green: CGFloat((rgb >> 8) & 255) / 255,
                       blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }

    static func hex(_ color: Color) -> String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }''')
edit('SourceReadSwift/App/RootTabView.swift','    @State private var selectedTab = 0','''    @AppStorage("settings.accentHex") private var accentHex = "594FDB"
    @AppStorage("settings.secondaryAccentHex") private var secondaryAccentHex = "419BDC"
    @Environment(\\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tabSelection
    @State private var selectedTab = 0''')
edit('SourceReadSwift/App/RootTabView.swift','        ZStack(alignment: .bottom) {','''        let _ = accentHex
        let _ = secondaryAccentHex
        return ZStack(alignment: .bottom) {''')
edit('SourceReadSwift/App/RootTabView.swift','        .animation(.easeOut(duration: 0.16), value: selectedTab)','        .tint(AppTheme.accent)')
edit('SourceReadSwift/App/RootTabView.swift','                        .fill(AppTheme.accent.opacity(0.12))','''                        .fill(AppTheme.accent.opacity(0.12))
                        .matchedGeometryEffect(id: "selected-tab", in: tabSelection)''')
edit('SourceReadSwift/App/RootTabView.swift','        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {','        withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.84)) {')
edit('SourceReadSwift/Features/Settings/SettingsView.swift','    @State private var cacheSize', '''    @AppStorage("settings.accentHex") private var accentHex = "594FDB"
    @AppStorage("settings.secondaryAccentHex") private var secondaryAccentHex = "419BDC"
    @State private var cacheSize''')
edit('SourceReadSwift/Features/Settings/SettingsView.swift','                Section("排版与字体") {','''                Section("自定义外观") {
                    ColorPicker("主题主色", selection: Binding(get: { AppTheme.accent }, set: { if let hex = AppTheme.hex($0) { accentHex = hex } }), supportsOpacity: false)
                    ColorPicker("主题辅色", selection: Binding(get: { AppTheme.secondaryAccent }, set: { if let hex = AppTheme.hex($0) { secondaryAccentHex = hex } }), supportsOpacity: false)
                    HStack(spacing: 8) {
                        ForEach(["594FDB", "267A62", "B75473", "B76A2C", "3476B8"], id: \\.self) { hex in
                            Button { accentHex = hex } label: {
                                Circle().fill(Color(uiColor: colorFromHex(hex))).frame(width: 30, height: 30)
                                    .overlay(Circle().strokeBorder(.primary.opacity(accentHex == hex ? 0.8 : 0), lineWidth: 2))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(.plain).accessibilityLabel("主题色 \\(hex)")
                        }
                    }
                    Button("恢复纸间默认配色") { accentHex = "594FDB"; secondaryAccentHex = "419BDC" }
                    Text("只调整应用界面配色，不覆盖书籍的阅读背景和字体颜色。").font(.caption).foregroundStyle(.secondary)
                }

                Section("排版与字体") {''')
p=R/'SourceReadSwift/Features/Settings/SettingsView.swift';s=p.read_text(encoding='utf8')
a=s.index('                Section("最近诊断") {');b=s.index('\n            }\n            .scrollDismissesKeyboard',a)
s=s[:a]+'''                Section("诊断") {
                    NavigationLink {
                        RecentDiagnosticsView(events: appState.diagnostics).hideRootTabBar()
                    } label: {
                        Label("最近诊断 · 查看与复制", systemImage: "doc.text.magnifyingglass")
                    }
                }'''+s[b:]
a=s.index('    /// The settings screen used');b=s.index('    private func settingsHeroMetric',a)
s=s[:a]+'''    private func colorFromHex(_ hex: String) -> UIColor {
        let n = UInt32(hex, radix: 16) ?? 0x594FDB
        return UIColor(red: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
    }

    private var settingsHeroSection: some View {
        Section {
            HStack(spacing: 16) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(LinearGradient(colors: [AppTheme.accent, AppTheme.secondaryAccent], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 56)
                VStack(alignment: .leading, spacing: 5) {
                    Text("纸间").font(.system(size: 25, weight: .semibold, design: .serif))
                    Text("把时间留给阅读").font(.subheadline).foregroundStyle(.secondary)
                    Text(AppVersion.fullDisplayString).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

'''+s[b:]
p.write_text(s,encoding='utf8')
edit('SourceReadSwift/Core/Storage/SourceStore.swift','    @Published private(set) var sources: [BookSource] = []','''    private(set) var sourcesRevision: UInt64 = 0
    @Published private(set) var sources: [BookSource] = [] {
        didSet { sourcesRevision &+= 1 }
    }''')
edit('SourceReadSwift/Features/Discover/DiscoverView.swift','        let token = "\\(sources.count)|\\(sources.first?.bookSourceUrl ?? "")|\\(sources.last?.bookSourceUrl ?? "")"','        let token = String(appState?.sourceStore.sourcesRevision ?? 0)')
