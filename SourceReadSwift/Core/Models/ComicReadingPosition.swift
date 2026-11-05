import CryptoKit
import Foundation

/// A reading line inside one image, independent of its decoded display size.
struct ComicPageAnchor: Hashable, Sendable {
    let pageIndex: Int
    let fraction: Double

    init(pageIndex: Int, fraction: Double) {
        self.pageIndex = max(0, pageIndex)
        self.fraction = fraction.isFinite ? min(max(fraction, 0), 1) : 0
    }
}

/// Optional shelf metadata; request addresses and headers never enter this cursor.
struct ComicReadingPosition: Codable, Hashable, Sendable {
    let sourceKey: String
    let chapterKey: String
    let imageKey: String
    let pageIndex: Int
    let pageCount: Int
    let fraction: Double

    init(sourceURL: String, chapter: BookChapter, pages: [ComicPage], anchor: ComicPageAnchor) {
        sourceKey = Self.digest(sourceURL)
        chapterKey = Self.chapterKey(chapter)
        pageIndex = min(anchor.pageIndex, max(pages.count - 1, 0))
        pageCount = pages.count
        fraction = anchor.fraction
        imageKey = pages.indices.contains(pageIndex) ? Self.digest(pages[pageIndex].url) : ""
    }

    /// Matches image identity first, then falls back conservatively when resources change.
    func resolve(sourceURL: String, chapter: BookChapter, pages: [ComicPage]) -> ComicPageAnchor? {
        guard !pages.isEmpty, sourceKey == Self.digest(sourceURL), chapterKey == Self.chapterKey(chapter) else { return nil }
        if let matched = pages.firstIndex(where: { Self.digest($0.url) == imageKey }) {
            return ComicPageAnchor(pageIndex: matched, fraction: fraction)
        }
        let fallback = min(max(pageIndex, 0), pages.count - 1)
        // Signed addresses and local archive URLs change even when page order does not.
        return ComicPageAnchor(pageIndex: fallback, fraction: pageCount == pages.count ? fraction : 0)
    }

    private static func chapterKey(_ chapter: BookChapter) -> String {
        if let url = URL(string: chapter.url), url.scheme == "srcomic", url.host == "chapter",
           url.lastPathComponent.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil {
            return url.lastPathComponent
        }
        return digest(chapter.url)
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Updated without publishing per-pixel changes through the SwiftUI view tree.
final class ComicViewportPosition {
    var anchor = ComicPageAnchor(pageIndex: 0, fraction: 0)
}
