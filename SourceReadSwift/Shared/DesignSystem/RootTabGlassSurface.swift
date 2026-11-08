import SwiftUI

/// Shared translucent root chrome with an opaque accessibility fallback.
struct RootTabGlassSurface<Outline: InsettableShape>: ViewModifier {
    let outline: Outline
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder func body(content: Content) -> some View {
        if reducesTransparency || contrast == .increased {
            content
                .background(outline.fill(Color(uiColor: .secondarySystemBackground)))
                .overlay(outline.strokeBorder(.primary.opacity(0.20), lineWidth: 1).allowsHitTesting(false))
        } else {
            translucent(content)
        }
    }

    @ViewBuilder private func translucent(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: outline)
        } else {
            material(content)
        }
        #else
        material(content)
        #endif
    }

    private func material(_ content: Content) -> some View {
        content
            .background(outline.fill(.ultraThinMaterial))
            .overlay(outline.strokeBorder(.primary.opacity(0.10), lineWidth: 0.6).allowsHitTesting(false))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
    }
}
