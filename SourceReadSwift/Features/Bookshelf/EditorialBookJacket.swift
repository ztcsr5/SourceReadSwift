import SwiftUI

/// Shared book construction. Perspective changes by scene, not by a timer.
struct EditorialBookJacket<Cover: View>: View {
    enum Stance { case shelf, detail }

    let height: CGFloat
    let palette: FloatingDeskPalette
    let stance: Stance
    @ViewBuilder let cover: () -> Cover
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let corner = RoundedRectangle(cornerRadius: 8, style: .continuous)
        cover()
            .overlay(alignment: .leading) {
                LinearGradient(colors: [.black.opacity(0.28), palette.pearl.opacity(0.35), .clear],
                    startPoint: .leading, endPoint: .trailing)
                    .frame(width: 10)
            }
            .clipShape(corner)
            .overlay {
                corner.strokeBorder(palette.pearl.opacity(contrast == .increased ? 0.7 : 0.45), lineWidth: 0.5)
            }
            .background(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [palette.pearl, palette.glassTint, palette.pearl],
                        startPoint: .top, endPoint: .bottom))
                    .frame(width: 7, height: height - 7)
                    .offset(x: 4, y: 1)
            }
            .shadow(color: palette.shadow.opacity(contrast == .increased ? 0 : scheme == .dark ? 0.32 : 0.20),
                radius: 9, x: 6, y: 9)
            .rotation3DEffect(.degrees(stance == .shelf ? -9 : -5),
                axis: (x: 0, y: 1, z: 0), perspective: 0.28)
            .rotationEffect(.degrees(stance == .shelf ? -4 : -2))
            .accessibilityHidden(true)
    }
}
