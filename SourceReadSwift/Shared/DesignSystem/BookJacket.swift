import SwiftUI

/// Static page edges and a spine catchlight provide depth without animated blur or sensors.
struct BookJacket<Cover: View>: View {
    @ViewBuilder let cover: () -> Cover
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @AppMotion private var motion

    var body: some View {
        cover()
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    Rectangle().fill(.black.opacity(0.20)).frame(width: 3)
                    Rectangle().fill(.white.opacity(0.14)).frame(width: 1)
                }.allowsHitTesting(false)
            }
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color(uiColor: .systemGray5)).frame(width: 2).padding(.vertical, 5)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
            .shadow(color: .black.opacity(contrast == .increased ? 0 : scheme == .dark ? 0.30 : 0.16), radius: 8, x: 4, y: 8)
            .rotation3DEffect(.degrees(motion.reducesMotion ? 0 : -5), axis: (x: 0, y: 1, z: 0), perspective: 0.3)
    }
}
