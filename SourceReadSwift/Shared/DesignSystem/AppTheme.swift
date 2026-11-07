import SwiftUI
import UIKit

enum AppTheme {
    static var background: Color {
        if UserDefaults.standard.string(forKey: "settings.themeMode") == "eyeCare" {
            return Color(red: 0.90, green: 0.95, blue: 0.88)
        }
        let theme = AppVisualTheme.current
        return theme.dynamicColor(light: theme.backgroundHex, dark: theme.darkBackgroundHex)
    }
    static var card: Color {
        let theme = AppVisualTheme.current
        return theme.dynamicColor(light: theme.cardHex, dark: theme.darkCardHex)
    }
    static var elevatedCard: Color { card }
    static var cardBackground: Color { card }
    static var accentUIColor: UIColor {
        let theme = AppVisualTheme.current
        return color(for: theme.preferenceKey("accent"), fallback: theme.accentHex, darkFallback: theme.darkAccentHex)
    }
    static var accent: Color { Color(uiColor: accentUIColor) }
    static var secondaryAccent: Color {
        let theme = AppVisualTheme.current
        return Color(uiColor: color(for: theme.preferenceKey("secondaryAccent"), fallback: theme.secondaryHex,
                                    darkFallback: theme.darkSecondaryHex))
    }
    static var softBlue: Color { secondaryAccent.opacity(0.16) }

    static func color(for key: String, fallback: UInt32, darkFallback: UInt32? = nil) -> UIColor {
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        guard raw.count == 6, let rgb = UInt32(raw, radix: 16), rgb != fallback else {
            return UIColor { traits in
                AppVisualTheme.uiColor(traits.userInterfaceStyle == .dark ? darkFallback ?? fallback : fallback)
            }
        }
        return AppVisualTheme.uiColor(rgb)
    }

    static func hex(_ color: Color) -> String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
    static let secondaryText = Color.secondary
    static let danger = Color(uiColor: .systemRed)

    static var cardRadius: CGFloat { AppVisualTheme.current.radius }
    static let pagePadding: CGFloat = AppLayout.pageMargin
    static let capsuleRadius: CGFloat = 16
}

extension View {
    func pageBackground() -> some View {
        modifier(PageBackgroundModifier())
    }

    func podcastCard() -> some View {
        padding(AppLayout.cardInset)
            .glassPanel(cornerRadius: AppTheme.cardRadius, material: .thinMaterial)
    }

    func glassPanel(
        cornerRadius: CGFloat? = nil,
        material: Material = .ultraThinMaterial,
        strokeOpacity: Double = 0.10,
        shadowOpacity: Double = 0.08,
        usesLiveMaterial: Bool = false
    ) -> some View {
        modifier(AppThemeSurface(cornerRadius: cornerRadius, material: material,
                                 strokeOpacity: strokeOpacity, shadowOpacity: shadowOpacity,
                                 usesLiveMaterial: usesLiveMaterial))
    }

    func listRowCard(cornerRadius: CGFloat = 16) -> some View {
        background(AppTheme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    func glassCircle(material: Material = .ultraThinMaterial) -> some View {
        modifier(AppThemeSurface(cornerRadius: 999, material: material,
                                 strokeOpacity: 0.15, shadowOpacity: 0.06, usesLiveMaterial: true))
    }
}

private struct PageBackgroundModifier: ViewModifier {
    @AppStorage("settings.themeMode") private var themeModeRawValue = ThemeMode.system.rawValue

    @AppStorage(AppVisualTheme.selectionKey) private var visualTheme = AppVisualTheme.initialSelection.rawValue
    @AppStorage("settings.appearanceRevision") private var appearanceRevision = 0

    func body(content: Content) -> some View {
        _ = visualTheme
        _ = appearanceRevision
        _ = themeModeRawValue
        return content
            .scrollContentBackground(.hidden)
            .font(.system(.body, design: AppVisualTheme.current.fontDesign))
            .tint(AppTheme.accent)
            .background {
                AppPagePaper(theme: AppVisualTheme.current).ignoresSafeArea()
            }
    }
}

/// Use existing book-paper artwork without changing the reader's own wallpaper.
struct AppPagePaper: View {
    let theme: AppVisualTheme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            AppTheme.background
            if contrast != .increased, let asset = theme.illustratedPaper?.wallpaperAssetName {
                ReaderIllustratedBackgroundView(name: asset, paper: AppTheme.background, night: scheme == .dark)
                    .id(asset)
                    .opacity(scheme == .dark ? 0.65 : 0.26)
            }
            AppThemeOrnament(theme: theme)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PodcastSectionTitle: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 34, weight: .bold, design: AppVisualTheme.current.fontDesign))
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PodcastLargeTitleBar<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 32, weight: .bold, design: AppVisualTheme.current.fontDesign))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            trailing()
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PodcastChevronSectionHeader: View {
    let title: String
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    label
                }
                .buttonStyle(.plain)
            } else {
                label
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var label: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

/// End editing anywhere in the app.
func dismissKeyboardNow() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}

extension View {
    func dismissKeyboard() {
        dismissKeyboardNow()
    }

    /// Ends editing when the user taps blank space, not only when they drag.
    ///
    /// `scrollDismissesKeyboard` reacts to a scroll gesture alone, so the search
    /// screens kept the keyboard up until Return. The gesture is simultaneous so
    /// result rows, chips and buttons keep receiving their own taps.
    func dismissKeyboardOnTap() -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                dismissKeyboardNow()
            }
        )
    }
}

struct CenterTextEmptyState: View {
    let text: String
    var minHeight: CGFloat

    init(_ text: String, minHeight: CGFloat = 220) {
        self.text = text
        self.minHeight = minHeight
    }

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: minHeight)
    }
}
