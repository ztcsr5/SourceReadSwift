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
        let corner = RoundedRectangle(cornerRadius: stance == .shelf ? 6 : 8, style: .continuous)
        cover()
            .overlay(alignment: .leading) {
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.33), location: 0),
                    .init(color: palette.pearl.opacity(0.24), location: 0.28),
                    .init(color: .black.opacity(0.10), location: 0.63),
                    .init(color: .clear, location: 1)
                ], startPoint: .leading, endPoint: .trailing)
                    .frame(width: stance == .shelf ? 9 : 8)
            }
            .clipShape(corner)
            .overlay {
                corner.strokeBorder(palette.pearl.opacity(contrast == .increased ? 0.7 : 0.45), lineWidth: 0.5)
            }
            .background(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [palette.shadow.opacity(0.56), palette.pearl, palette.light, palette.shadow.opacity(0.34)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: stance == .shelf ? 10 : 7, height: height - 8)
                    .offset(x: stance == .shelf ? 6 : 4, y: 2)
            }
            .shadow(color: palette.shadow.opacity(contrast == .increased ? 0 : scheme == .dark ? 0.32 : 0.20),
                radius: stance == .shelf ? 8 : 9, x: 7, y: 8)
            .rotation3DEffect(.degrees(stance == .shelf ? -9 : -5),
                axis: (x: 0, y: 1, z: 0), perspective: 0.28)
            .rotationEffect(.degrees(stance == .shelf ? -4 : -2))
            .accessibilityHidden(true)
    }
}
