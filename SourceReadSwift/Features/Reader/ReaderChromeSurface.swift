import SwiftUI

/// One material per panel. Nesting glass on every button obscures both labels
/// and the paper beneath it; accessibility always has an opaque escape hatch.
struct ReaderChromeSurface: ViewModifier {
    let paper: Color
    let ink: Color
    var cornerRadius: CGFloat = 24
    @Environment(\.readingEdition) private var skin
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("reader.menuSurfaceStyle") private var menuStyle = "system"
    @AppStorage("reader.menuUsesWallpaper") private var usesWallpaper = false
    @AppStorage("reader.menuPaperOpacity") private var paperOpacity = 0.97
    @AppStorage("reader.background") private var backgroundRaw = ReaderBackground.white.rawValue
    @AppStorage(PerformanceMode.defaultsKey) private var performanceMode = false

    private var surfaceShape: AnyShape {
        if let skin, cornerRadius < 900 {
            return AnyShape(EditionContour(skin: skin))
        }
        return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    static func permitsTranslucency(reduceTransparency: Bool, increasedContrast: Bool,
                                    menuStyle: String, usesWallpaper: Bool,
                                    performanceMode: Bool = false) -> Bool {
        _ = usesWallpaper
        return !performanceMode && !reduceTransparency && !increasedContrast && menuStyle == "system"
    }

    static func usesNativeGlass(reduceTransparency: Bool, increasedContrast: Bool = false,
                                menuStyle: String = "system", usesWallpaper: Bool = false,
                                performanceMode: Bool = false) -> Bool {
        supportsNativeGlass && permitsTranslucency(reduceTransparency: reduceTransparency,
            increasedContrast: increasedContrast, menuStyle: menuStyle,
            usesWallpaper: usesWallpaper, performanceMode: performanceMode)
    }

    private static var supportsNativeGlass: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    @ViewBuilder func body(content: Content) -> some View {
        Group {
            if !Self.permitsTranslucency(reduceTransparency: reduceTransparency, increasedContrast: contrast == .increased,
                menuStyle: menuStyle, usesWallpaper: usesWallpaper, performanceMode: performanceMode) {
                opaque(content)
            } else {
                translucent(content)
            }
        }
        .overlay {
            if let skin, cornerRadius < 900 {
                EditionCornerTrim(skin: skin, ink: ink, inset: 7)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            EditionPanelTrim(ink: ink)
        }
    }

    @ViewBuilder private func translucent(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), Self.supportsNativeGlass {
            content.glassEffect(.regular, in: surfaceShape)
                .overlay {
                    editionBorderOverlay(isTranslucent: true)
                }
        } else {
            material(content)
        }
        #else
        material(content)
        #endif
    }

    private func material(_ content: Content) -> some View {
        content
            .background {
                surfaceShape.fill(.ultraThinMaterial)
            }
            .overlay {
                editionBorderOverlay(isTranslucent: true)
            }
    }

    private func opaque(_ content: Content) -> some View {
        content
            .background {
                ZStack {
                    paper
                    if usesWallpaper {
                        if backgroundRaw == ReaderBackground.custom.rawValue, let image = ReaderCustomWallpaperStore.cachedWallpaper {
                            ReaderWallpaperView(image: image, fillMode: ReaderCustomWallpaperStore.adjustment.fillMode,
                                adjustment: ReaderCustomWallpaperStore.adjustment, isNight: colorScheme == .dark)
                                .opacity(1 - min(max(paperOpacity, 0.85), 1))
                        } else {
                            let background = ReaderBackground(rawValue: backgroundRaw) ?? .white
                            ReaderPaperTextureView(background: background, night: colorScheme == .dark)
                                .opacity(1 - min(max(paperOpacity, 0.85), 1))
                        }
                    }
                }.clipShape(surfaceShape)
            }
            .overlay {
                editionBorderOverlay(isTranslucent: false)
            }
    }

    @ViewBuilder
    private func editionBorderOverlay(isTranslucent: Bool) -> some View {
        if let skin, cornerRadius < 900 {
            let lineColor = ink.opacity(skin == .blade ? (isTranslucent ? 0.42 : 0.56) : (isTranslucent ? 0.24 : 0.34))
            ZStack {
                surfaceShape
                    .stroke(
                        lineColor,
                        style: skin == .bunny
                            ? StrokeStyle(lineWidth: 1.4, dash: [5, 3])
                            : StrokeStyle(lineWidth: skin == .blade ? 1.45 : 1.0)
                    )
                if skin == .ink {
                    surfaceShape
                        .stroke(ink.opacity(0.14), lineWidth: 0.7)
                        .padding(3)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else if !isTranslucent {
            surfaceShape
                .stroke(ink.opacity(0.18), lineWidth: 0.6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(ink.opacity(0.12), lineWidth: 0.6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Show visual contact immediately, without haptics or rerendering the glass.
struct ReaderControlPressStyle: ButtonStyle {
    @AppMotion private var motion
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.readingEdition) private var skin

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = isEnabled && configuration.isPressed
        configuration.label
            .modifier(EditionPressFeedback(isPressed: isPressed, skin: skin, motion: motion,
                                          defaultScale: 0.965))
    }
}
