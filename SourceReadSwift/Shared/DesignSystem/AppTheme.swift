import SwiftUI
import UIKit

enum AppTheme {
    static var background: Color {
        let theme = AppVisualTheme.current
        return theme.dynamicColor(light: theme.backgroundHex, dark: theme.darkBackgroundHex)
    }

    static var card: Color {
        let theme = AppVisualTheme.current
        return theme.dynamicColor(light: theme.cardHex, dark: theme.darkCardHex)
    }

    static var accent: Color { Color(uiColor: accentUIColor) }

    static var accentUIColor: UIColor {
        let theme = AppVisualTheme.current
        return color(for: theme.preferenceKey("accent"), fallback: theme.accentHex, darkFallback: theme.darkAccentHex)
    }

    static var prominentFill: Color { AppVisualTheme.current.atelierPalette?.emphasisFill ?? accent }
    static var prominentInk: Color { AppVisualTheme.current.atelierPalette?.emphasisInk ?? .white }

    static var secondaryAccent: Color {
        let theme = AppVisualTheme.current
        return Color(uiColor: color(for: theme.preferenceKey("secondaryAccent"),
                                    fallback: theme.secondaryHex, darkFallback: theme.darkSecondaryHex))
    }

    static var secondaryAccentHex: String { hex(secondaryAccent) ?? "419BDC" }

    static func color(for key: String, fallback: UInt32, darkFallback: UInt32? = nil) -> UIColor {
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        guard raw.count == 6, let rgb = UInt32(raw, radix: 16), rgb != fallback else {
            return UIColor { traits in
                AppVisualTheme.uiColor(traits.userInterfaceStyle == .dark ? darkFallback ?? fallback : fallback)
            }
        }
        return UIColor { traits in
            guard traits.userInterfaceStyle == .dark else {
                return AppVisualTheme.uiColor(rgb)
            }
            if let darkRaw = UserDefaults.standard.string(forKey: key + ".dark"),
               let darkRGB = parseHexDigits(darkRaw) {
                return AppVisualTheme.uiColor(darkRGB)
            }
            return AppVisualTheme.uiColor(adaptiveDarkHex(from: rgb))
        }
    }

    private static func parseHexDigits(_ raw: String) -> UInt32? {
        guard raw.count == 6 else { return nil }
        var value: UInt32 = 0
        for scalar in raw.unicodeScalars {
            let nibble: UInt32
            switch scalar.value {
            case 48...57: nibble = scalar.value - 48
            case 65...70: nibble = scalar.value - 55
            case 97...102: nibble = scalar.value - 87
            default: return nil
            }
            value = (value << 4) | nibble
        }
        return value
    }

    private static func adaptiveDarkHex(from lightRGB: UInt32) -> UInt32 {
        let r = Double((lightRGB >> 16) & 255) / 255.0
        let g = Double((lightRGB >> 8) & 255) / 255.0
        let b = Double(lightRGB & 255) / 255.0
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        guard luminance < 0.35 else { return lightRGB }
        let lift = 0.58
        let nr = UInt32(((r + (1.0 - r) * lift) * 255.0).rounded())
        let ng = UInt32(((g + (1.0 - g) * lift) * 255.0).rounded())
        let nb = UInt32(((b + (1.0 - b) * lift) * 255.0).rounded())
        return (nr << 16) | (ng << 8) | nb
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
                    .stroke(Color.primary.opacity(0.075), lineWidth: 0.75)
            }
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
    @AppStorage(HomeCompositionPreference.storageKey) private var homeCompositionRaw = HomeCompositionPreference.autoRawValue

    func body(content: Content) -> some View {
        _ = visualTheme
        _ = appearanceRevision
        _ = themeModeRawValue
        _ = homeCompositionRaw
        let current = AppVisualTheme.current
        return content
            .scrollContentBackground(.hidden)
            .font(.system(.body, design: current.fontDesign))
            .tint(AppTheme.accent)
            .background {
                AppPagePaper(theme: current).ignoresSafeArea()
            }
    }
}

/// Use curated paper / atmospheric artwork without overriding the reader's own wallpaper.
struct AppPagePaper: View {
    let theme: AppVisualTheme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("settings.appearanceRevision") private var revision = 0

    var body: some View {
        let _ = revision
        ZStack {
            AppTheme.background
            if theme == .custom {
                AppCustomBackdropLayer(preset: AppCustomThemeStore.shared.activePreset, isDark: scheme == .dark)
            } else if contrast != .increased, let atmospheric = theme.atmosphericPaperAsset(isDark: scheme == .dark) {
                ReaderIllustratedBackgroundView(name: atmospheric, paper: AppTheme.background, night: scheme == .dark)
                    .id(atmospheric)
                    .opacity(scheme == .dark ? 0.88 : 0.78)
                    .overlay {
                        LinearGradient(
                            colors: [
                                AppTheme.background.opacity(scheme == .dark ? 0.12 : 0.14),
                                AppTheme.background.opacity(scheme == .dark ? 0.42 : 0.46),
                                AppTheme.background.opacity(scheme == .dark ? 0.12 : 0.14),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            } else if contrast != .increased, let asset = theme.illustratedPaper?.wallpaperAssetName {
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

private struct AppCustomBackdropLayer: View {
    let preset: CustomThemePreset
    let isDark: Bool
    @State private var photo: UIImage?

    private var targetFilename: String? {
        isDark ? (preset.darkImageFilename ?? preset.lightImageFilename) : preset.lightImageFilename
    }

    var body: some View {
        Group {
            switch preset.backdropKind {
            case .solid:
                Color(uiColor: AppVisualTheme.uiColor(isDark ? preset.darkSolidHex : preset.lightSolidHex))
            case .gradient:
                LinearGradient(
                    colors: [
                        Color(uiColor: AppVisualTheme.uiColor(isDark ? preset.darkGradientStartHex : preset.gradientStartHex)),
                        Color(uiColor: AppVisualTheme.uiColor(isDark ? preset.darkGradientEndHex : preset.gradientEndHex)),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .photo:
                ZStack {
                    if let activePhoto = photo ?? AppCustomThemeStore.cachedImage(filename: targetFilename, blurRadius: preset.blurRadius) {
                        Image(uiImage: activePhoto)
                            .resizable()
                            .scaledToFill()
                    }
                    (isDark ? Color.black : Color.white)
                        .opacity(isDark ? preset.darkDimming : preset.lightDimming)
                }
                .task(id: "\(targetFilename ?? "")-\(Int(preset.blurRadius))") {
                    photo = await AppCustomThemeStore.loadImage(filename: targetFilename, blurRadius: preset.blurRadius)
                }
            }
        }
    }
}

struct PodcastSectionTitle: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppVisualTheme.current.titleFont(size: 34, weight: .bold))
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
                .font(AppVisualTheme.current.titleFont(size: 32, weight: .bold))
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
