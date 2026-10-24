import CoreGraphics
import Foundation

/// Legado ruleContent.imageStyle - how chapter illustrations are sized.
///
/// Legado documents the field as "默认大小：FULL 铺满"; the full set of
/// accepted values in ReadBook is DEFAULT / FULL / TEXT / SINGLE.
/// SINGLE is a pagination concept (one illustration per page), which maps to
/// full width, vertically centred, never taller than the viewport on iOS.
enum ReaderImageStyle: String, CaseIterable, Sendable {
    case standard = "DEFAULT"
    case full = "FULL"
    case text = "TEXT"
    case single = "SINGLE"

    /// Unknown or missing rule values fall back to DEFAULT, matching Legado.
    init(rule: String?) {
        let normalized = (rule ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        self = ReaderImageStyle(rawValue: normalized) ?? .standard
    }

    /// FULL stretches every illustration to the text column width; the other
    /// styles only shrink illustrations that are wider than the column.
    var stretchesToColumnWidth: Bool {
        self == .full || self == .single
    }

    /// SINGLE reserves a whole page for one illustration.
    var reservesWholePage: Bool { self == .single }

    var displayName: String {
        switch self {
        case .standard: return "默认"
        case .full: return "铺满"
        case .text: return "文本"
        case .single: return "单图独占一页"
        }
    }
}

/// Mirrors TextChapterLayout.setImage sizing so the native TextKit surface and
/// the SwiftUI page surface agree on illustration geometry.
enum ReaderImageSizingPolicy {
    /// Caption row ("点击查看插图大图"), its VStack gap and the vertical
    /// padding drawn by `ReaderIllustrationView`. Pagination budgets the whole
    /// card, not just the bitmap.
    static let pagedCaptionHeight: CGFloat = 44

    static func size(
        for imageSize: CGSize,
        style: ReaderImageStyle,
        containerWidth: CGFloat,
        maximumHeight: CGFloat? = nil
    ) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, containerWidth > 0 else { return .zero }
        var width = imageSize.width
        var height = imageSize.height
        if style.stretchesToColumnWidth || width > containerWidth {
            height = imageSize.height * containerWidth / imageSize.width
            width = containerWidth
        }
        if let maximumHeight, maximumHeight > 0, height > maximumHeight {
            width = width * maximumHeight / height
            height = maximumHeight
        }
        return CGSize(width: max(width, 1), height: max(height, 1))
    }

    /// Estimated vertical cost of an illustration in the text pagination
    /// model. Pagination runs before the bitmap is downloaded, so it reserves
    /// a deterministic fraction of the page instead of measuring pixels.
    static func estimatedPageCost(for style: ReaderImageStyle, pageBudget: Int) -> Int {
        let budget = max(pageBudget, 1)
        switch style {
        case .single:
            return budget
        case .full:
            return Int(Double(budget) * 0.72)
        case .standard, .text:
            return Int(Double(budget) * 0.46)
        }
    }

    /// Legado clamps illustrations to the visible page height. SINGLE keeps a
    /// larger share because it owns the page; DEFAULT/TEXT leave room for text.
    static func maximumHeight(for style: ReaderImageStyle, viewportHeight: CGFloat) -> CGFloat {
        let ratio: CGFloat = style.reservesWholePage ? 0.78 : 0.62
        return max(viewportHeight * ratio, 160)
    }

    /// Paged surfaces reserve the reader's top breathing room and the bottom
    /// chrome inside their own layout.  Deriving the image ceiling from the
    /// same budget keeps a SINGLE illustration from overflowing the page now
    /// that paged pages can no longer scroll.
    static func maximumHeight(
        for style: ReaderImageStyle,
        viewportHeight: CGFloat,
        pagePadding: Double,
        footerHeight: Double
    ) -> CGFloat {
        let available = max(viewportHeight - CGFloat(pagePadding * 2 + footerHeight) - 96, 160)
        if style.reservesWholePage { return available }
        return min(available, max(viewportHeight * 0.62, 160))
    }

    /// The [img]url[/img] paragraph body, or nil when the paragraph is text.
    static func imageURL(in paragraph: String) -> URL? {
        // Source rules frequently leave blank lines around an illustration
        // marker. Trim once here so pagination, the SwiftUI page and the
        // TextKit scroll surface all make the same decision.
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[img]"), trimmed.hasSuffix("[/img]") else { return nil }
        let raw = String(trimmed.dropFirst(5).dropLast(6))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw), let scheme = url.scheme, !scheme.isEmpty else { return nil }
        return url
    }
}
