import SwiftUI

/// Shared book construction. Perspective changes by scene, not by a timer.
struct EditorialBookJacket<Cover: View>: View {
    enum Stance { case shelf, detail, floating }

    let height: CGFloat
    let palette: FloatingDeskPalette
    let stance: Stance
    @ViewBuilder let cover: () -> Cover
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let corner = RoundedRectangle(cornerRadius: stance == .detail ? 6 : 3, style: .continuous)
        cover()
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    Rectangle().fill(.black.opacity(0.26)).frame(width: 2)
                    Rectangle().fill(palette.pearl.opacity(0.24)).frame(width: 0.75)
                    Rectangle().fill(.black.opacity(0.08)).frame(width: 4)
                }.allowsHitTesting(false)
            }
            .clipShape(corner)
            .overlay {
                corner.strokeBorder(palette.pearl.opacity(contrast == .increased ? 0.7 : 0.45), lineWidth: 0.5)
            }
            .background(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(palette.pearl)
                    .overlay { RoundedRectangle(cornerRadius: 1).strokeBorder(palette.shadow.opacity(0.36), lineWidth: 0.75) }
                    .frame(width: stance == .floating ? 7 : stance == .shelf ? 5 : 4, height: height - 5)
                    .offset(x: stance == .floating ? 5 : stance == .shelf ? 3 : 2, y: 2)
            }
            .shadow(color: palette.shadow.opacity(contrast == .increased ? 0 : scheme == .dark ? 0.32 : 0.20),
                radius: stance == .floating ? 5 : stance == .shelf ? 6 : 8, x: stance == .floating ? 3 : 5,
                y: stance == .floating ? 4 : 7)
            .rotation3DEffect(.degrees(stance == .shelf ? -9 : stance == .floating ? -12 : -5),
                axis: (x: 0, y: 1, z: 0), perspective: 0.28)
            .rotationEffect(.degrees(stance == .shelf ? -3 : stance == .floating ? -4 : -2))
            .accessibilityHidden(true)
    }
}
