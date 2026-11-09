import SwiftUI

/// A row observes palette changes itself, including inside an already-open sheet.
struct AppThemeRowSurface: View {
    @AppStorage(AppVisualTheme.selectionKey) private var theme = AppVisualTheme.initialSelection.rawValue
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

    static func resolve(theme: AppVisualTheme, nativeGlassAvailable: Bool, reduceTransparency: Bool,
                        increasedContrast: Bool, performanceMode: Bool = false) -> Self {
        guard !performanceMode else { return .paper }
        guard theme.supportsLiveGlass, !reduceTransparency, !increasedContrast else { return .paper }
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
    var usesLiveMaterial = false
    @AppStorage(AppVisualTheme.selectionKey) private var themeRawValue = AppVisualTheme.initialSelection.rawValue
    @AppStorage("settings.appearanceRevision") private var appearanceRevision = 0
    @AppStorage(PerformanceMode.defaultsKey) private var performanceMode = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var theme: AppVisualTheme { AppVisualTheme(rawValue: themeRawValue) ?? .classic }

    @ViewBuilder func body(content: Content) -> some View {
        let _ = appearanceRevision
        let _ = performanceMode
        let radius = theme.surfaceRadius(preferred: cornerRadius)
        // Repeated scrolling cards are opaque paper. Reserve live backdrop
        // sampling for a few explicit floating controls, not every list row.
        let style: AppThemeSurfaceStyle = usesLiveMaterial ? AppThemeSurfaceStyle.resolve(theme: theme,
            nativeGlassAvailable: AppThemeSurfaceStyle.nativeGlassAvailable,
            reduceTransparency: reduceTransparency, increasedContrast: contrast == .increased,
            performanceMode: performanceMode) : .paper
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

    @ViewBuilder
    private func legacy(_ content: Content, radius: CGFloat, style: AppThemeSurfaceStyle) -> some View {
        let surface = content.background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            if style == .legacyMaterial { shape.fill(material) }
            else { shape.fill(AppTheme.card) }
        }
        .overlay { AppThemeOrnament(theme: theme, isCard: true) }
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.primary.opacity(contrast == .increased ? max(strokeOpacity, 0.35) : theme.isAtelier ? min(strokeOpacity, 0.06) : strokeOpacity),
                        lineWidth: theme.borderWidth)
                .allowsHitTesting(false)
        }
        .clipShape(AppThemeCardShape(theme: theme, radius: radius), style: FillStyle(eoFill: true))
        // A zero-opacity shadow is not free: SwiftUI still installs the
        // shadow layer and every scrolling row pays for its offscreen pass.
        // Leave the modifier off entirely when a caller opted out of depth.
        if shadowOpacity > 0, !performanceMode, !theme.isAtelier, theme != .inkwash, theme != .blueprint {
            surface.shadow(color: .black.opacity(shadowOpacity), radius: 6, x: 0, y: 3)
        } else {
            surface
        }
    }
}
