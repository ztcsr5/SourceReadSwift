import SwiftUI

enum ComicChromePalette {
    static let secondaryInkOpacity = 0.82
    static let controlFill = Color.white.opacity(0.12)
    // Comic art is arbitrary, so white controls cannot depend on its luminance.
    static let backing = Color.black.opacity(0.90)
}

/// A bounded material surface for white comic chrome, independent of the app theme.
struct ComicChromeSurface<Outline: Shape>: View {
    let shape: Outline

    var body: some View {
        shape.fill(.ultraThinMaterial)
            .overlay { shape.fill(ComicChromePalette.backing) }
    }
}
