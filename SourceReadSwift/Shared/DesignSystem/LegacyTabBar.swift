import SwiftUI

/// Universal floating tab bar with aligned global search button.
struct LegacyTabBar: View {
    @Binding var selection: Int
    var onSearch: () -> Void
    @AppMotion private var motion
    @Namespace private var highlight
    @AppStorage(AppVisualTheme.selectionKey) private var themeRaw = AppVisualTheme.initialSelection.rawValue
    private var theme: AppVisualTheme { AppVisualTheme(rawValue: themeRaw) ?? .classic }

    var body: some View {
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
            .background {
                if theme.usesNeutralGlass { BrandGlass(outline: Capsule()) }
                else if theme.isAtelier { Capsule().fill(AppTheme.card) }
                else { Capsule().fill(.regularMaterial) }
            }
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.6).allowsHitTesting(false))
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(theme.primaryInk)
                    .frame(width: 52, height: 52)
                    .background {
                        if theme.isAtelier { Circle().fill(AppTheme.card) }
                        else { Circle().fill(.regularMaterial) }
                    }
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))
                    .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(AppPressStyle())
            .accessibilityLabel("全网搜书")
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
            .foregroundStyle(selection == value ? AppTheme.accent : theme.usesNeutralGlass ? theme.secondaryInk : .primary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background {
                ZStack {
                    if selection == value {
                        Capsule().fill(theme.usesNeutralGlass ? theme.controlFill : AppTheme.accent.opacity(0.12))
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
