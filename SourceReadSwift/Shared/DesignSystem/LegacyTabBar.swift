import SwiftUI

/// Universal floating tab bar with aligned global search button.
struct LegacyTabBar: View {
    @Binding var selection: Int
    var onSearch: () -> Void
    @AppMotion private var motion
    @Namespace private var highlight

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
            .modifier(RootTabGlassSurface(outline: Capsule()))
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .modifier(RootTabGlassSurface(outline: Circle(), isInteractive: true))
                    .contentShape(Circle())
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
            .foregroundStyle(selection == value ? AppTheme.accent : .primary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background {
                ZStack {
                    if selection == value {
                        Capsule().fill(AppTheme.accent.opacity(0.12))
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
