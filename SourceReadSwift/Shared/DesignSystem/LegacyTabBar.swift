import SwiftUI

/// iOS 16–25 only. Native iOS 26 TabView remains owned by RootTabView.
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
                else { Capsule().fill(.regularMaterial) }
            }
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.6).allowsHitTesting(false))
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(theme.primaryInk)
                    .frame(width: 54, height: 54)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.6))
            }
            .buttonStyle(AppPressStyle())
            .accessibilityLabel("全网搜书")
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
