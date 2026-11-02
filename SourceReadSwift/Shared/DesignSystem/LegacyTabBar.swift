import SwiftUI

/// iOS 16–25 only. Native iOS 26 TabView remains owned by RootTabView.
struct LegacyTabBar: View {
    @Binding var selection: Int
    var onSearch: () -> Void
    @AppMotion private var motion
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                tab(0, title: "主页", icon: "house")
                tab(1, title: AppNavigationLabels.findBooks, icon: AppNavigationLabels.findBooksSymbol)
                tab(2, title: "设置", icon: "gearshape")
            }
            .padding(4)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.6))
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(.primary)
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
            withAnimation(motion.animation(.navigation)) {
                selection = value
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: selection == value ? icon + ".fill" : icon).font(.system(size: 21, weight: .medium))
                    .scaleEffect(selection == value && !motion.reducesMotion ? 1.04 : 1)
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(selection == value ? AppTheme.accent : .primary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background {
                if selection == value {
                    Capsule().fill(AppTheme.accent.opacity(0.12))
                        .matchedGeometryEffect(id: "selection", in: highlight)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(AppPressStyle())
        .accessibilityAddTraits(selection == value ? [.isSelected] : [])
    }
}
