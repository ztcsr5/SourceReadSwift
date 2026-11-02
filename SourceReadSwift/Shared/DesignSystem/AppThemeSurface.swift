import SwiftUI

/// A row observes palette changes itself, including inside an already-open sheet.
struct AppThemeRowSurface: View {
    @AppStorage("settings.visualTheme") private var theme = AppVisualTheme.classic.rawValue
    @AppStorage("settings.appearanceRevision") private var revision = 0
    var body: some View {
        let _ = theme
        let _ = revision
        return AppTheme.card
    }
}

enum AppThemeSurfaceStyle: Equatable {
    case paper, legacyMaterial, nativeGlass

    static var nativeGlassAvailable: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    static func resolve(theme: AppVisualTheme, nativeGlassAvailable: Bool, reduceTransparency: Bool, increasedContrast: Bool) -> Self {
        guard theme == .classic, !reduceTransparency, !increasedContrast else { return .paper }
        return nativeGlassAvailable ? .nativeGlass : .legacyMaterial
    }
}

/// Observe appearance here as well as at the root: an already-presented sheet
/// must update without changing identity, dismissing its editor or losing focus.
struct AppThemeSurface: ViewModifier {
    let cornerRadius: CGFloat?
    let material: Material
    let strokeOpacity: Double
    let shadowOpacity: Double
    @AppStorage("settings.visualTheme") private var themeRawValue = AppVisualTheme.classic.rawValue
    @AppStorage("settings.appearanceRevision") private var appearanceRevision = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var theme: AppVisualTheme { AppVisualTheme(rawValue: themeRawValue) ?? .classic }

    @ViewBuilder func body(content: Content) -> some View {
        let _ = appearanceRevision
        let radius = cornerRadius ?? theme.radius
        let style = AppThemeSurfaceStyle.resolve(theme: theme,
            nativeGlassAvailable: AppThemeSurfaceStyle.nativeGlassAvailable,
            reduceTransparency: reduceTransparency, increasedContrast: contrast == .increased)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), style == .nativeGlass {
            content.glassEffect(.regular.tint(AppTheme.card.opacity(0.25)),
                                in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            legacy(content, radius: radius, style: style)
        }
        #else
        legacy(content, radius: radius, style: style)
        #endif
    }

    private func legacy(_ content: Content, radius: CGFloat, style: AppThemeSurfaceStyle) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            if style == .legacyMaterial { shape.fill(material) }
            else { shape.fill(AppTheme.card) }
        }
        .overlay { AppThemeOrnament(theme: theme, isCard: true) }
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.primary.opacity(contrast == .increased ? max(strokeOpacity, 0.35) : strokeOpacity),
                        lineWidth: theme.borderWidth)
                .allowsHitTesting(false)
        }
        .clipShape(AppThemeCardShape(theme: theme, radius: radius), style: FillStyle(eoFill: true))
        .shadow(color: .black.opacity(theme == .inkwash || theme == .blueprint ? 0 : shadowOpacity), radius: 6, x: 0, y: 3)
    }
}
