from pathlib import Path
R=Path(__file__).resolve().parents[2]
p=R/'SourceReadSwift/Shared/DesignSystem/AppTheme.swift';s=p.read_text(encoding='utf8')
s=s.replace(': Color(.systemGroupedBackground)',': AppVisualTheme.current.dynamicColor(light: AppVisualTheme.current.backgroundHex, dark: AppVisualTheme.current.darkBackgroundHex)')
s=s.replace('static let card = Color(.systemBackground)','static var card: Color { AppVisualTheme.current.dynamicColor(light: AppVisualTheme.current.cardHex, dark: AppVisualTheme.current.darkCardHex) }')
s=s.replace('static let elevatedCard = Color(.secondarySystemGroupedBackground)','static var elevatedCard: Color { card }').replace('static let cardBackground = Color(.secondarySystemBackground)','static var cardBackground: Color { card }')
s=s.replace('color(for: "settings.accentHex", fallback: 0x594FDB)','color(for: AppVisualTheme.current.preferenceKey("accent"), fallback: AppVisualTheme.current.accentHex)')
s=s.replace('color(for: "settings.secondaryAccentHex", fallback: 0x419BDC)','color(for: AppVisualTheme.current.preferenceKey("secondaryAccent"), fallback: AppVisualTheme.current.secondaryHex)')
s=s.replace('static let cardRadius: CGFloat = 18','static var cardRadius: CGFloat { AppVisualTheme.current.radius }')
# The classic theme retains its material. Other themes intentionally have
# opaque card stocks, reducing overlapping backdrop filters while scrolling.
a=s.index('        background(material, in: RoundedRectangle',s.index('    func glassPanel('))
s=s[:a]+s[a:].replace('        background(material, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))','''        background {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            if AppVisualTheme.current == .classic { shape.fill(material) }
            else { shape.fill(AppTheme.card) }
        }''',1)
s=s.replace('lineWidth: 0.8\n                    )','lineWidth: AppVisualTheme.current.borderWidth\n                    )',1)
s=s.replace('background(Color(uiColor: .secondarySystemGroupedBackground), in:', 'background(AppTheme.card, in:')
s=s.replace('    func body(content: Content) -> some View {\n        _ = themeModeRawValue', '''    @AppStorage("settings.visualTheme") private var visualTheme = AppVisualTheme.classic.rawValue
    @AppStorage("settings.appearanceRevision") private var appearanceRevision = 0

    func body(content: Content) -> some View {
        _ = visualTheme
        _ = appearanceRevision
        _ = themeModeRawValue''')
p.write_text(s,encoding='utf8')
p=R/'SourceReadSwift/Features/Settings/SettingsView.swift';s=p.read_text(encoding='utf8');a=s.index('                Image(systemName: "book.closed.fill")',s.index('private var settingsHeroSection'));b=s.index('\n                VStack(alignment:',a);s=s[:a]+'                PaperBetweenMark()'+s[b:];p.write_text(s,encoding='utf8')
p=R/'SourceReadSwift/App/RootTabView.swift';s=p.read_text(encoding='utf8')
s=s.replace('    @ObservedObject private var audioCoordinator = AudioBookPlaybackCoordinator.shared','    private let audioCoordinator = AudioBookPlaybackCoordinator.shared\n    @State private var hasAudio = false',1)
s=s.replace('    @Environment(\\.accessibilityReduceMotion)', '    @AppStorage("settings.visualTheme") private var visualTheme = AppVisualTheme.classic.rawValue\n    @AppStorage("settings.appearanceRevision") private var appearanceRevision = 0\n    @Environment(\\.accessibilityReduceMotion)',1)
s=s.replace('        let _ = accentHex','        let _ = visualTheme\n        let _ = appearanceRevision\n        let _ = accentHex',1)
s=s.replace('audioCoordinator.currentBook != nil','hasAudio')
s=s.replace('        .tint(AppTheme.accent)','        .font(.system(.body, design: AppVisualTheme.current.fontDesign))\n        .tint(AppTheme.accent)\n        .onReceive(audioCoordinator.$currentBook.map { $0 != nil }.removeDuplicates()) { hasAudio = $0 }',1)
a=s.index('    private var miniAudioPlayerBar: some View {');b=s.index('    private var customTabBar:',a)
bar=s[a:b]
# Keep frequent AVPlayer progress observations local to the mini-player.
bar=bar.replace('    private var miniAudioPlayerBar: some View {','    var body: some View {',1)
s=s[:a]+'''    private var miniAudioPlayerBar: some View {
        RootMiniAudioPlayerBar(showFullAudioPlayer: $showFullAudioPlayer)
    }

'''+s[b:]
s+='''\nprivate struct RootMiniAudioPlayerBar: View {
    @ObservedObject private var audioCoordinator = AudioBookPlaybackCoordinator.shared
    @Binding var showFullAudioPlayer: Bool
'''+bar+'}\n'
p.write_text(s,encoding='utf8')
