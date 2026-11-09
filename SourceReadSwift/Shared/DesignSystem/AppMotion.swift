import SwiftUI

/// One motion vocabulary; reader pagination and navigation ownership stay outside it.
struct AppMotionPolicy: Equatable {
    enum Event { case press, navigation, expansion, background, bookmark }
    let reducesMotion: Bool

    func duration(_ event: Event) -> Double {
        switch event {
        case .press: return 0.14
        case .navigation: return 0.30
        case .expansion: return 0.28
        case .background: return 0.32
        case .bookmark: return 0.32
        }
    }

    func animation(_ event: Event) -> Animation? {
        guard !reducesMotion else { return nil }
        switch event {
        case .press, .background: return .easeInOut(duration: duration(event))
        case .navigation: return .interactiveSpring(response: duration(event), dampingFraction: 0.90)
        case .expansion: return .interactiveSpring(response: duration(event), dampingFraction: 0.88)
        case .bookmark: return .spring(response: duration(event), dampingFraction: 0.82)
        }
    }

    func arrivalAnimation(stage: Int) -> Animation? {
        animation(.expansion)?.delay(Double(min(max(stage, 0), 2)) * 0.045)
    }

    func backgroundAnimation(hasPreviousPalette: Bool, hasNextPalette: Bool) -> Animation? {
        // A light placeholder and a dark cover surface use different semantic ink.
        // Crossfading only the surface would temporarily put white text on white.
        hasPreviousPalette && hasNextPalette ? animation(.background) : nil
    }
}

/// Combines the system accessibility preference and the app's explicit opt-out.
@propertyWrapper struct AppMotion: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var systemReducesMotion
    @AppStorage("settings.reducesMotion") private var appReducesMotion = false
    var wrappedValue: AppMotionPolicy { AppMotionPolicy(reducesMotion: systemReducesMotion || appReducesMotion) }
}

struct AppPressStyle: ButtonStyle {
    @AppMotion private var motion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !motion.reducesMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(motion.animation(.press), value: configuration.isPressed)
    }
}

/// Native zoom owns displacement; a second scale animation causes a visible handoff bump.
struct BookOpenPressStyle: ButtonStyle {
    @AppMotion private var motion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.88 : 1)
            .animation(motion.animation(.press), value: configuration.isPressed)
    }
}

/// Only the system navigation transition owns the hero and its interactive return.
private struct BookHeroSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    @AppMotion private var motion
    @ViewBuilder func body(content: Content) -> some View {
        // The zoom handoff is a navigation transition, not part of the spatial
        // reading desk. Turning the desk off must not silently downgrade every
        // shelf -> detail push to a plain slide.
        if #available(iOS 18.0, *), !motion.reducesMotion {
            content.matchedTransitionSource(id: id, in: namespace)
        } else { content }
    }
}

private struct BookHeroDestination: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    let enabled: Bool
    @AppMotion private var motion
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *), enabled, !motion.reducesMotion {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else { content }
    }
}

extension View {
    func bookHeroSource(_ id: String, in namespace: Namespace.ID) -> some View {
        modifier(BookHeroSource(id: id, namespace: namespace))
    }
    func bookHeroDestination(_ id: String, in namespace: Namespace.ID, enabled: Bool = true) -> some View {
        modifier(BookHeroDestination(id: id, namespace: namespace, enabled: enabled))
    }
}
