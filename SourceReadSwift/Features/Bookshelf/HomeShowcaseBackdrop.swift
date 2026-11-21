import SwiftUI
import UIKit

/// One cover-derived glass wash spans the page, including the navigation bar.
struct HomeShowcaseBackdrop: View {
    let book: BookshelfBook
    let theme: AppVisualTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @State private var image: UIImage?

    private var coverURL: URL? {
        CoverURLResolver.url(from: book.coverURL, base: book.bookURL, fallbackBase: book.sourceURL)
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if reducesTransparency {
                    theme.controlFill
                } else {
                    Group {
                        if let image { Image(uiImage: image).resizable().scaledToFill() }
                        else { theme.controlFill }
                    }
                        .frame(width: geometry.size.width, height: min(geometry.size.height, geometry.size.width * 1.9))
                        .clipped()
                        .overlay { AppTheme.background.opacity(0.12) }
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
        .task(id: reducesTransparency ? nil : coverURL) {
            guard let coverURL, !reducesTransparency else { image = nil; return }
            let prepared = await CoverGlassBackdropStore.preparedImage(for: coverURL)
            guard !Task.isCancelled else { return }
            image = prepared
        }
    }
}
