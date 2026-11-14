import SwiftUI

/// One material per panel. Nesting glass on every button obscures both labels
/// and the paper beneath it; accessibility always has an opaque escape hatch.
struct ReaderChromeSurface: ViewModifier {
    let paper: Color
    let ink: Color
    var protectsReadingControls = false
    var cornerRadius: CGFloat = 24
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("reader.menuSurfaceStyle") private var menuStyle = "system"
    @AppStorage("reader.menuUsesWallpaper") private var usesWallpaper = false
    @AppStorage("reader.menuPaperOpacity") private var paperOpacity = 0.97
    @AppStorage("reader.background") private var backgroundRaw = ReaderBackground.white.rawValue
    @AppStorage(PerformanceMode.defaultsKey) private var performanceMode = false

    static func permitsTranslucency(reduceTransparency: Bool, increasedContrast: Bool,
                                    menuStyle: String, usesWallpaper: Bool,
                                    performanceMode: Bool = false) -> Bool {
        _ = usesWallpaper
        return !performanceMode && !reduceTransparency && !increasedContrast && menuStyle == "system"
    }

    static func usesNativeGlass(reduceTransparency: Bool, increasedContrast: Bool = false,
                                menuStyle: String = "system", usesWallpaper: Bool = false,
                                performanceMode: Bool = false) -> Bool {
        guard permitsTranslucency(reduceTransparency: reduceTransparency, increasedContrast: increasedContrast,
            menuStyle: menuStyle, usesWallpaper: usesWallpaper, performanceMode: performanceMode) else { return false }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    @ViewBuilder func body(content: Content) -> some View {
        if Self.permitsTranslucency(reduceTransparency: reduceTransparency, increasedContrast: contrast == .increased,
            menuStyle: menuStyle, usesWallpaper: usesWallpaper, performanceMode: performanceMode) {
            translucent(content)
        } else {
            opaque(content)
        }
    }

    @ViewBuilder private func translucent(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(paper.opacity(glassTintOpacity)),
                                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            material(content)
        }
        #else
        material(content)
        #endif
    }

    private var glassTintOpacity: Double {
        // Unify top/bottom reader chrome & P3 settings card with the navigation
        // bar crystal-clear Liquid Glass clarity (0.10-0.16 subtle tint, never 0.66 fog).
        if protectsReadingControls { return colorScheme == .dark ? 0.16 : 0.14 }
        return colorScheme == .dark ? 0.12 : 0.10
    }

    private func material(_ content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                shape.fill(.regularMaterial)
                    .overlay { shape.fill(paper.opacity(legacyTintOpacity)) }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ink.opacity(0.12), lineWidth: 0.6).allowsHitTesting(false)
            }
    }

    private var legacyTintOpacity: Double {
        if protectsReadingControls { return colorScheme == .dark ? 0.16 : 0.14 }
        return glassTintOpacity
    }

    private func opaque(_ content: Content) -> some View {
        content
            .background {
                ZStack {
                    paper
                    if usesWallpaper {
                        if backgroundRaw == ReaderBackground.custom.rawValue, let image = ReaderCustomWallpaperStore.cachedWallpaper {
                            ReaderWallpaperView(image: image, fillMode: ReaderCustomWallpaperStore.adjustment.fillMode,
                                adjustment: ReaderCustomWallpaperStore.adjustment)
                                .opacity(1 - min(max(paperOpacity, 0.85), 1))
                        } else {
                            let background = ReaderBackground(rawValue: backgroundRaw) ?? .white
                            ReaderPaperTextureView(background: background, night: background.isDark)
                                .opacity(1 - min(max(paperOpacity, 0.85), 1))
                        }
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(ink.opacity(0.18), lineWidth: 0.6)
                    .allowsHitTesting(false)
            }
    }
}
