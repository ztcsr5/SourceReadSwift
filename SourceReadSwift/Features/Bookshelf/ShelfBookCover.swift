import SwiftUI

enum ShelfCoverGeometry {
    /// Keep the cover and page block in one 2:3 silhouette at every shelf size.
    static func size(maxWidth: CGFloat?, height: CGFloat) -> CGSize {
        let width = min(max(maxWidth ?? .greatestFiniteMagnitude, 1), max(height, 1) * 2 / 3)
        return CGSize(width: width, height: width * 1.5)
    }
}

/// The raster, spine and page edges share their bounds and transform together.
struct ShelfBookCover: View {
    let book: BookshelfBook
    let width: CGFloat?
    let height: CGFloat

    var body: some View {
        let size = ShelfCoverGeometry.size(maxWidth: width, height: height)
        EditorialBookJacket(height: size.height, palette: .resolve(theme: AppVisualTheme.current), stance: .shelf) {
            AsyncBookCover(urlString: book.coverURL, width: size.width, height: size.height,
                baseURLString: book.bookURL, sourceURLString: book.sourceURL,
                title: book.title, contentMode: .fill, cornerRadius: 3, usesPlainPlaceholder: true)
        }
        .frame(width: size.width, height: size.height)
        .padding(.vertical, 4)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// A quiet typeset jacket when the source supplies no image.
struct PlainShelfJacket: View {
    let title: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(title?.nilIfEmpty ?? "未命名书籍")
            .font(.caption.weight(.medium))
            .lineLimit(2)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(scheme == .dark ? Color(white: 0.88) : Color(white: 0.19))
            .background(Color(uiColor: AppVisualTheme.uiColor(scheme == .dark ? 0x33332F : 0xEFEEE8)))
    }
}
