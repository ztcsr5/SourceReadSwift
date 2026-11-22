import SwiftUI

/// Broad, stationary color fields suggest frosted glass without a live blur pass.
struct ForestGlassBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let forest = AppVisualTheme.forest
        GeometryReader { geometry in
            if !reducesTransparency, contrast != .increased {
                LinearGradient(colors: [forest.mistPaper, forest.mistTint, forest.mistPaper],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        RadialGradient(colors: [forest.mistTint.opacity(scheme == .dark ? 0.8 : 0.7), .clear],
                            center: .init(x: 0.15, y: 0.3), startRadius: 0,
                            endRadius: max(geometry.size.width, geometry.size.height) * 0.65)
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
