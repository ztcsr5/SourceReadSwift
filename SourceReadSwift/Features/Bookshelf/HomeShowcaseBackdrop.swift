import SwiftUI

/// One cover-derived glass wash spans the page, including the navigation bar.
struct HomeShowcaseBackdrop: View {
    let book: BookshelfBook
    let theme: AppVisualTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency

    var body: some View {
        GeometryReader { geometry in
            Group {
                if reducesTransparency {
                    theme.controlFill
                } else {
                    CachedRemoteImage(url: CoverURLResolver.url(from: book.coverURL,
                        base: book.bookURL, fallbackBase: book.sourceURL),
                        maxPixelSize: 96, reuseCoverBytes: true) { theme.controlFill }
                        .frame(width: geometry.size.width, height: min(geometry.size.height, geometry.size.width * 1.9))
                        .clipped()
                        .blur(radius: 32, opaque: true)
                        .overlay { Rectangle().fill(.ultraThinMaterial).opacity(0.25) }
                        .opacity(colorScheme == .dark ? 0.28 : 0.85)
                }
            }
            .frame(width: geometry.size.width, height: min(geometry.size.height, geometry.size.width * 1.9))
            .mask {
                LinearGradient(stops: [.init(color: .white, location: 0),
                    .init(color: .white.opacity(0.88), location: 0.5),
                    .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
