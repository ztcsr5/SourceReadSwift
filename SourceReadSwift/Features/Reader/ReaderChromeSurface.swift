import SwiftUI

/// One material per panel. Nesting glass on every button obscures both labels
/// and the paper beneath it; accessibility always has an opaque escape hatch.
struct ReaderChromeSurface: ViewModifier {
    let paper: Color
    let ink: Color
    var protectsReadingControls = false
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
        !performanceMode && !reduceTransparency && !increasedContrast && menuStyle == "system" && !usesWallpaper
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
                                in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            material(content)
        }
        #else
        material(content)
        #endif
    }

    private var glassTintOpacity: Double {
        // Toolbars share one recipe; the larger settings surface needs
        // stronger diffusion so lines of prose cannot compete with controls.
        if protectsReadingControls { return colorScheme == .dark ? 0.70 : 0.66 }
        return 0.10
    }

    private func material(_ content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
                shape.fill(.regularMaterial)
                    .overlay { shape.fill(paper.opacity(legacyTintOpacity)) }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(ink.opacity(0.12), lineWidth: 0.6).allowsHitTesting(false)
            }
    }

    private var legacyTintOpacity: Double {
        // Regular Material already diffuses the page; the extra paper tint
        // must not make the user's glass choice indistinguishable from opaque paper.
        if protectsReadingControls, colorScheme == .light { return 0.58 }
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
