import SwiftUI

/// Shelves show the unmodified jacket; management and format remain outside it.
struct ShelfBookCover: View {
    let book: BookshelfBook
    let width: CGFloat?
    let height: CGFloat
    private let outline = RoundedRectangle(cornerRadius: 8, style: .continuous)

    var body: some View {
        AsyncBookCover(urlString: book.coverURL, width: width, height: height,
            baseURLString: book.bookURL, sourceURLString: book.sourceURL,
            title: book.title, contentMode: .fit, cornerRadius: 8, usesPlainPlaceholder: true)
        .background(AppVisualTheme.current.controlFill, in: outline)
        .overlay(outline.strokeBorder(AppVisualTheme.current.controlBorder, lineWidth: 0.6).allowsHitTesting(false))
        .accessibilityHidden(true)
    }
}

/// A quiet typeset jacket when the source supplies no image.
struct PlainShelfJacket: View {
    let title: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(title?.nilIfEmpty ?? "未命名书籍")
            .font(.system(.caption, design: .serif).weight(.medium))
            .lineLimit(2)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(scheme == .dark ? Color(white: 0.88) : Color(white: 0.19))
            .background(Color(uiColor: AppVisualTheme.uiColor(scheme == .dark ? 0x33332F : 0xEFEEE8)))
    }
}
