import SwiftUI
import UIKit

/// One cover-derived glass wash spans the page, including the navigation bar.
struct HomeShowcaseBackdrop: View {
    let book: BookshelfBook
    let theme: AppVisualTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @State private var image: UIImage?
    @State private var imageURL: URL?
    @Environment(\.colorSchemeContrast) private var contrast

    private var coverURL: URL? {
        CoverURLResolver.url(from: book.coverURL, base: book.bookURL, fallbackBase: book.sourceURL)
    }

    var body: some View {
        GeometryReader { geometry in
            if !reducesTransparency, contrast != .increased {
                if imageURL == coverURL, let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .overlay { AppTheme.background.opacity(colorScheme == .dark ? 0.86 : 0.80) }
                } else {
                    ForestGlassBackdrop()
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: reducesTransparency ? nil : coverURL) {
            guard let coverURL, !reducesTransparency else { image = nil; imageURL = nil; return }
            let prepared = await CoverGlassBackdropStore.preparedImage(for: coverURL,
                headers: CoverURLResolver.requestHeaders(for: coverURL, base: book.bookURL, fallbackBase: book.sourceURL))
            guard !Task.isCancelled else { return }
            image = prepared
            imageURL = coverURL
        }
    }
}
