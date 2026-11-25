import SwiftUI

/// Static paper and light keep the four editions distinct without a live blur pass.
struct AntigravityPageBackdrop: View {
    let theme: AppVisualTheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency

    private var paper: Color { theme.dynamicColor(light: theme.cardHex, dark: theme.darkCardHex) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                paper
                if contrast != .increased, !reducesTransparency {
                    LinearGradient(stops: [
                        .init(color: theme.controlFill, location: 0),
                        .init(color: paper, location: theme == .hardcoverStudy ? 0.70 : 0.48),
                        .init(color: paper, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    if theme == .inkstone {
                        windowLight(width: geometry.size.width)
                    } else if theme == .hardcoverStudy {
                        RadialGradient(colors: [AppTheme.accent.opacity(0.10), .clear],
                            center: .topLeading, startRadius: 0, endRadius: geometry.size.width)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func windowLight(width: CGFloat) -> some View {
        VStack(spacing: 48) {
            ForEach(0..<2) { _ in
                LinearGradient(colors: [theme.primaryInk.opacity(0.045), .clear],
                    startPoint: .top, endPoint: .bottom)
                    .frame(width: width * 1.6, height: 24)
            }
        }
        .rotationEffect(.degrees(28))
        .offset(x: -width * 0.18, y: 64)
    }
}
