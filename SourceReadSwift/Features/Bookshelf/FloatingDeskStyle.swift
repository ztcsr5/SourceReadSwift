import SwiftUI

/// Semantic atmosphere for the reading desk only; it never rewrites the global theme.
struct FloatingDeskPalette {
    let pearl: Color
    let mist: Color
    let light: Color
    let ink: Color
    let shadow: Color
    let glassTint: Color

    static func resolve(theme: AppVisualTheme) -> Self {
        if theme == .classic {
            return Self(pearl: theme.dynamicColor(light: 0xFAF8FF, dark: 0x201D2C),
                mist: AppTheme.accent, light: theme.dynamicColor(light: 0xDAD0F5, dark: 0x75638F),
                ink: theme.dynamicColor(light: 0x352644, dark: 0xF3EDFF),
                shadow: theme.dynamicColor(light: 0x51416E, dark: 0x000000),
                glassTint: theme.dynamicColor(light: 0xEEE8FC, dark: 0x352C49))
        }
        return Self(pearl: AppTheme.card, mist: AppTheme.accent, light: AppTheme.secondaryAccent,
            ink: theme.dynamicColor(light: 0x29282D, dark: 0xF5F3EF),
            shadow: theme.dynamicColor(light: theme.accentHex, dark: 0x000000), glassTint: AppTheme.card)
    }
}

/// Accessibility and energy policy is independent of book/reader state.
struct FloatingDeskPolicy: Equatable {
    enum Surface: Equatable { case opaque, material, liquidGlass }
    struct Preferences {
        let reducesMotion: Bool
        let reducesTransparency: Bool
        let increasedContrast: Bool
        let conservesEnergy: Bool
    }
    let reducesDepth: Bool
    let surface: Surface

    static func resolve(_ preferences: Preferences, hasLiquidGlass: Bool) -> Self {
        let opaque = preferences.reducesTransparency || preferences.increasedContrast || preferences.conservesEnergy
        return Self(reducesDepth: preferences.reducesMotion || preferences.conservesEnergy,
                    surface: opaque ? .opaque : hasLiquidGlass ? .liquidGlass : .material)
    }
}

/// Render-only displacement: no gesture recognizer, layout publication or per-frame sampling.
struct FloatingDeskParallax: ViewModifier {
    let depth: CGFloat
    let reducesDepth: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 17.0, *), !reducesDepth {
            content.visualEffect { effect, geometry in
                let phase = Self.phase(geometry)
                effect.offset(x: -phase * depth, y: abs(phase) * depth * 0.22)
                    .scaleEffect(1 - abs(phase) * depth * 0.0015)
            }
        } else { content }
    }

    @available(iOS 17.0, *)
    private static func phase(_ geometry: GeometryProxy) -> CGFloat {
        guard let viewport = geometry.bounds(of: .scrollView(axis: .horizontal)), viewport.width > 0 else { return 0 }
        return min(max((geometry.size.width / 2 - viewport.midX) / viewport.width, -1), 1)
    }
}

private struct FloatingDeskPressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isFloatingDeskPressed: Bool {
        get { self[FloatingDeskPressedKey.self] }
        set { self[FloatingDeskPressedKey.self] = newValue }
    }
}

/// Only optical feedback during a press: the system zoom remains the sole owner of scale.
struct FloatingDeskPressStyle: ButtonStyle {
    var isEnabled = true
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if isEnabled { configuration.label.environment(\.isFloatingDeskPressed, configuration.isPressed) }
        else { BookOpenPressStyle().makeBody(configuration: configuration) }
    }
}
