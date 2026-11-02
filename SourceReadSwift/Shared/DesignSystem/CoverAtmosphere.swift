import SwiftUI

/// A static, cached-cover palette. Gradients animate only when a different cover arrives.
struct CoverAtmosphere: View {
    let tone: CoverTone?
    @Environment(\.colorSchemeContrast) private var contrast
    private var inkSurface: Color {
        guard let tone else { return Color(uiColor: .secondarySystemBackground) }
        return Color(red: max(0.025, tone.vividRed * 0.22), green: max(0.025, tone.vividGreen * 0.22), blue: max(0.025, tone.vividBlue * 0.22))
    }
    var body: some View {
        ZStack {
            if tone == nil { AppTheme.card } else { inkSurface }
            if contrast != .increased, let tone {
                RadialGradient(colors: [Color(red: tone.vividRed, green: tone.vividGreen, blue: tone.vividBlue).opacity(0.32), .clear],
                               center: .top, startRadius: 0, endRadius: 340)
            }
        }
        .allowsHitTesting(false)
    }
}
