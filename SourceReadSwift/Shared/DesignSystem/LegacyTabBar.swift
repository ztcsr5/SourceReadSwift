import SwiftUI

/// Universal floating tab bar with aligned global search button.
struct LegacyTabBar: View {
    @Binding var selection: Int
    var onSearch: () -> Void
    @AppStorage(AppVisualTheme.selectionKey) private var themeRaw = AppVisualTheme.initialSelection.rawValue
    @AppStorage("settings.appearanceRevision") private var revision = 0
    @AppMotion private var motion
    @Namespace private var highlight

    private var theme: AppVisualTheme { AppVisualTheme.migrated(from: themeRaw) }

    var body: some View {
        let _ = revision
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                tab(0, title: "主页", icon: "house")
                    .accessibilityIdentifier("tabs.legacy.home")
                tab(1, title: AppNavigationLabels.findBooks, icon: AppNavigationLabels.findBooksSymbol)
                    .accessibilityIdentifier("tabs.legacy.discover")
                tab(2, title: "设置", icon: "gearshape")
                    .accessibilityIdentifier("tabs.legacy.settings")
            }
            .padding(4)
            .modifier(RootTabGlassSurface(outline: Capsule()))
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(theme == .pineSootMagazine ? AppTheme.prominentInk : theme.primaryInk)
                    .frame(width: 52, height: 52)
                    .modifier(EditionSearchSurface(theme: theme))
                    .contentShape(Circle())
            }
            .buttonStyle(AppPressStyle())
            .accessibilityLabel("搜书")
            .accessibilityIdentifier("bookshelf.globalSearch")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func tab(_ value: Int, title: String, icon: String) -> some View {
        Button {
            guard selection != value else { return }
            HapticFeedback.light()
            selection = value
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 21, weight: .medium))
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(selection == value ? (theme == .pineSootMagazine ? AppTheme.prominentInk : AppTheme.accent) : theme.primaryInk)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background {
                ZStack {
                    if selection == value {
                        Capsule().fill(theme == .pineSootMagazine ? AppTheme.accent : theme.usesNeutralGlass ? theme.controlFill : AppTheme.accent.opacity(0.12))
                            .matchedGeometryEffect(id: "selection", in: highlight)
                    }
                }
                .animation(motion.animation(.navigation), value: selection)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(AppPressStyle())
        .accessibilityAddTraits(selection == value ? [.isSelected] : [])
    }
}

private struct EditionSearchSurface: ViewModifier {
    let theme: AppVisualTheme
    @ViewBuilder func body(content: Content) -> some View {
        if theme == .pineSootMagazine { content.background(AppTheme.accent, in: Circle()) }
        else { content.modifier(RootTabGlassSurface(outline: Circle(), isInteractive: true)) }
    }
}
