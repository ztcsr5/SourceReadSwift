import SwiftUI

/// A static, cached-cover palette. Gradients animate only when a different cover arrives.
struct CoverAtmosphere: View {
    let tone: CoverTone?
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    @AppStorage("settings.visualTheme") private var theme = AppVisualTheme.classic.rawValue
    @AppStorage("settings.appearanceRevision") private var revision = 0
    var body: some View {
        ZStack {
            let _ = theme
            let _ = revision
            AppTheme.card
            if contrast != .increased {
                let pigment = tone.map { Color(red: $0.vividRed, green: $0.vividGreen, blue: $0.vividBlue) } ?? AppTheme.accent
                // The theme remains the paper; the cover contributes only a restrained wash.
                LinearGradient(colors: [pigment.opacity(scheme == .dark ? 0.14 : 0.09), .clear, AppTheme.background.opacity(0.45)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [pigment.opacity(scheme == .dark ? 0.16 : 0.08), .clear],
                    center: .leading, startRadius: 0, endRadius: 240)
            }
        }
        .allowsHitTesting(false)
    }
}
