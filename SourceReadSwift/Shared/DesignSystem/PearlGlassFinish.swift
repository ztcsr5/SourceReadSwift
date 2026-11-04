import SwiftUI

/// A static finish shared by the desk and the compatibility bar.
struct PearlGlassFinish<Outline: InsettableShape>: ViewModifier {
    let outline: Outline
    let pearl: Color
    let mist: Color
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency

    func body(content: Content) -> some View {
        content.overlay {
            if contrast != .increased, !reducesTransparency {
                outline.fill(LinearGradient(stops: [
                    .init(color: pearl.opacity(scheme == .dark ? 0.20 : 0.57), location: 0),
                    .init(color: pearl.opacity(scheme == .dark ? 0.06 : 0.18), location: 0.28),
                    .init(color: .clear, location: 0.57),
                    .init(color: mist.opacity(scheme == .dark ? 0.14 : 0.18), location: 1)
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    outline.strokeBorder(LinearGradient(colors: [
                        pearl.opacity(scheme == .dark ? 0.38 : 0.82),
                        mist.opacity(0.12),
                        pearl.opacity(scheme == .dark ? 0.12 : 0.32)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}
