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

    /// The [img]url[/img] paragraph body, or nil when the paragraph is text.
    static func imageURL(in paragraph: String) -> URL? {
        guard paragraph.hasPrefix("[img]"), paragraph.hasSuffix("[/img]") else { return nil }
        let raw = String(paragraph.dropFirst(5).dropLast(6))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw) else { return nil }
        return url
    }
}
