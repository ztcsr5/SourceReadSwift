import SwiftUI

/// Crop the book's own cover beneath a legible vertical title, never squeeze its front cover.
struct HomeBookSpine: View {
    let book: BookshelfBook
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            Text(Self.titleLines(for: book.title))
                .font(.caption.weight(.medium)).lineLimit(10)
            Spacer(minLength: 0)
            if book.title.prefix(7).count <= 6, let author = book.author.nilIfEmpty {
                Text(Self.titleLines(for: String(author.prefix(5)))).font(.caption2).lineLimit(5)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 12)
        .frame(width: width, height: height)
        .background {
            CachedRemoteImage(url: CoverURLResolver.url(from: book.coverURL,
                base: book.bookURL, fallbackBase: book.sourceURL),
                maxPixelSize: 96, reuseCoverBytes: true) { Color.secondary }
                .overlay { Color.black.opacity(0.65) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
            LinearGradient(colors: [.white.opacity(0.20), .clear, .black.opacity(0.24)],
                startPoint: .leading, endPoint: .trailing)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .accessibilityHidden(true)
    }

    /// Bound the visible title while the enclosing book action exposes its full accessible name.
    static func titleLines(for title: String) -> String {
        let glyphs = Array((title.nilIfEmpty ?? "未命名书籍").prefix(11))
        let visible = glyphs.count > 10 ? Array(glyphs.prefix(9)) + ["…"] : glyphs
        return visible.map(String.init).joined(separator: "\n")
    }
}
