import UIKit
import ObjectiveC

enum HapticFeedback {
    static var isEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: "app.hapticsEnabled") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "app.hapticsEnabled")
        }
    }

    @MainActor
    static func light() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @MainActor
    static func medium() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    @MainActor
    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @MainActor
    static func warning() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    @MainActor
    static func error() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

extension UIImpactFeedbackGenerator {
    private static let swizzleImpactOccurredOnce: Void = {
        let originalSelector = #selector(UIImpactFeedbackGenerator.impactOccurred as (UIImpactFeedbackGenerator) -> () -> Void)
        let swizzledSelector = #selector(UIImpactFeedbackGenerator.sr_impactOccurredNoArgs)
        if let originalMethod = class_getInstanceMethod(UIImpactFeedbackGenerator.self, originalSelector),
           let swizzledMethod = class_getInstanceMethod(UIImpactFeedbackGenerator.self, swizzledSelector) {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }

        let originalIntensitySelector = #selector(UIImpactFeedbackGenerator.impactOccurred(intensity:))
        let swizzledIntensitySelector = #selector(UIImpactFeedbackGenerator.sr_impactOccurredWithIntensity(_:))
        if let origM = class_getInstanceMethod(UIImpactFeedbackGenerator.self, originalIntensitySelector),
           let swizM = class_getInstanceMethod(UIImpactFeedbackGenerator.self, swizzledIntensitySelector) {
            method_exchangeImplementations(origM, swizM)
        }
    }()

    static func initializeHapticsControl() {
        _ = swizzleImpactOccurredOnce
    }

    @objc private func sr_impactOccurredNoArgs() {
        guard HapticFeedback.isEnabled else { return }
        sr_impactOccurredNoArgs()
    }

    @objc private func sr_impactOccurredWithIntensity(_ intensity: CGFloat) {
        guard HapticFeedback.isEnabled else { return }
        sr_impactOccurredWithIntensity(intensity)
    }
}

extension UINotificationFeedbackGenerator {
    private static let swizzleNotificationOccurredOnce: Void = {
        let originalSelector = #selector(UINotificationFeedbackGenerator.notificationOccurred(_:))
        let swizzledSelector = #selector(UINotificationFeedbackGenerator.sr_notificationOccurred(_:))
        if let originalMethod = class_getInstanceMethod(UINotificationFeedbackGenerator.self, originalSelector),
           let swizzledMethod = class_getInstanceMethod(UINotificationFeedbackGenerator.self, swizzledSelector) {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }()

    static func initializeNotificationHapticsControl() {
        _ = swizzleNotificationOccurredOnce
    }

    @objc private func sr_notificationOccurred(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard HapticFeedback.isEnabled else { return }
        sr_notificationOccurred(type)
    }
}
