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
                theme.hasBoundEdition ? theme.dynamicColor(light: theme.backgroundHex, dark: theme.darkBackgroundHex) : paper
                if theme == .hardcoverStudy, contrast != .increased, !reducesTransparency {
                    LinearGradient(stops: [
                        .init(color: theme.dynamicColor(light: 0xCBDED7, dark: 0x2C3D36), location: 0),
                        .init(color: theme.dynamicColor(light: 0xE9EAE0, dark: 0x222D27), location: 0.23),
                        .init(color: .clear, location: 0.60)
                    ], startPoint: .topLeading, endPoint: .bottom)
                } else if !theme.hasBoundEdition, contrast != .increased, !reducesTransparency {
                    LinearGradient(stops: [
                        .init(color: theme.controlFill, location: 0),
                        .init(color: paper, location: 0.48),
                        .init(color: paper, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    if theme == .inkstone {
                        windowLight(width: geometry.size.width)
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
