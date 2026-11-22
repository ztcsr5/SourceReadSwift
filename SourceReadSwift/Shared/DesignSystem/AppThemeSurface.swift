import SwiftUI

/// A row observes palette changes itself, including inside an already-open sheet.
struct AppThemeRowSurface: View {
    @AppStorage(AppVisualTheme.selectionKey) private var theme = AppVisualTheme.initialSelection.rawValue
    @AppStorage("settings.appearanceRevision") private var revision = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let _ = theme
        let _ = revision
        let current = AppVisualTheme.current
        if current == .custom {
            let preset = AppCustomThemeStore.shared.activePreset
            if preset.cardSurface == .glass {
                AppTheme.card.opacity(preset.cardOpacity)
            } else {
                AppTheme.card
            }
        } else if current.usesTintedPaper {
            AppTheme.card.opacity(current.glassCardOpacity(reducesTransparency: reducesTransparency,
                increasedContrast: contrast == .increased))
        } else if current.usesNeutralGlass {
            AppTheme.card
        } else {
            AppTheme.card.opacity(scheme == .dark ? 0.92 : 0.95)
        }
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
    @Environment(\.colorScheme) private var scheme

    private var theme: AppVisualTheme { AppVisualTheme.migrated(from: themeRawValue) }

    @ViewBuilder func body(content: Content) -> some View {
        let _ = appearanceRevision
        let _ = performanceMode
        let radius = theme.surfaceRadius(preferred: cornerRadius)
        let style: AppThemeSurfaceStyle = usesLiveMaterial ? AppThemeSurfaceStyle.resolve(
            theme: theme,
            nativeGlassAvailable: AppThemeSurfaceStyle.nativeGlassAvailable,
            reduceTransparency: reduceTransparency,
            increasedContrast: contrast == .increased,
            performanceMode: performanceMode
        ) : .paper
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), style == .nativeGlass {
            let tintOpacity = theme.usesNeutralGlass ? 0.14 : 0.20
            content
                .glassEffect(.regular.tint(AppTheme.card.opacity(tintOpacity)),
                             in: AppThemeCardShape(theme: theme, radius: radius))
                .overlay {
                    if let skin = ReadingEditionSkin(theme: theme) {
                        EditionCornerTrim(skin: skin, ink: AppTheme.accent)
                    }
                }
        } else {
            legacy(content, radius: radius, style: style)
        }
        #else
        legacy(content, radius: radius, style: style)
        #endif
    }

    @ViewBuilder
    private func legacy(_ content: Content, radius: CGFloat, style: AppThemeSurfaceStyle) -> some View {
        let resolvedStrokeOpacity: Double = {
            if contrast == .increased { return max(strokeOpacity, 0.35) }
            if theme.usesNeutralGlass { return 1 }
            if theme.isAtelier { return min(strokeOpacity, 0.06) }
            if let skin = ReadingEditionSkin(theme: theme) {
                return max(strokeOpacity, skin == .blade ? 0.30 : skin == .ink ? 0.22 : 0.18)
            }
            return strokeOpacity
        }()
        let shape = AppThemeCardShape(theme: theme, radius: radius)
        let surface = content.background {
            if style == .legacyMaterial {
                shape.fill(material)
            } else if theme.usesTintedPaper {
                shape.fill(AppTheme.card.opacity(theme.glassCardOpacity(reducesTransparency: reduceTransparency,
                    increasedContrast: contrast == .increased)))
            } else if theme == .custom, AppCustomThemeStore.currentPreset.cardSurface == .glass {
                shape.fill(AppTheme.card.opacity(AppCustomThemeStore.currentPreset.cardOpacity))
            } else {
                shape.fill(AppTheme.card)
            }
        }
        .overlay { AppThemeOrnament(theme: theme, isCard: true) }
        .overlay {
            if let skin = ReadingEditionSkin(theme: theme) {
                EditionCornerTrim(skin: skin, ink: AppTheme.accent)
            }
        }
        .overlay {
            if resolvedStrokeOpacity > 0, theme.borderWidth > 0 {
                shape
                    .stroke(theme.usesNeutralGlass && contrast != .increased
                            ? theme.controlBorder : Color.primary.opacity(resolvedStrokeOpacity),
                            lineWidth: ReadingEditionSkin(theme: theme) == .blade ? max(theme.borderWidth, 1.15) : theme.borderWidth)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(shape, style: FillStyle(eoFill: true))

        if shadowOpacity > 0, !performanceMode, !theme.isAtelier, theme != .inkwash, !(theme.usesNeutralGlass && scheme == .light) {
            surface.shadow(color: .black.opacity(shadowOpacity), radius: 6, x: 0, y: 3)
        } else {
            surface
        }
    }
}
