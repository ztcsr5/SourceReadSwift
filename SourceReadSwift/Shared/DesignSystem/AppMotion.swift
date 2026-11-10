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

/// 动效不再可关闭：App 内「减少动态效果」开关已删除。
/// `reducesMotion` 字段保留为恒 `false`，只是为了不改动 30 余处
/// `motion.reducesMotion ? … : …` 调用点，行为上等同于恒常动效。
@propertyWrapper struct AppMotion: DynamicProperty {
    var wrappedValue: AppMotionPolicy { AppMotionPolicy(reducesMotion: false) }
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
/// 开卷 zoom 不做任何降级开关：一旦被抑制，push 会静默退回普通滑入，
/// 现场表现就是「点了书籍没有任何转场」。
private struct BookHeroSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    @ViewBuilder func body(content: Content) -> some View {
        // The zoom handoff is a navigation transition, not part of the spatial
        // reading desk. Turning the desk off must not silently downgrade every
        // shelf -> detail push to a plain slide.
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else { content }
    }
}

private struct BookHeroDestination: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    let enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *), enabled {
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
