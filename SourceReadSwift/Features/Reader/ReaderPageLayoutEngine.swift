import CoreGraphics
import Foundation
import UIKit

/// Typography inputs shared by the paged surface and its pagination pass.
///
/// The old estimator assumed ~0.56em per character.  That is reasonable for
/// Latin text and wrong by almost 2x for Chinese, so a "page" held far more
/// text than SwiftUI could draw.  The paged surface used to hide the mistake
/// inside a vertical ScrollView; now that pages are fixed, measurement must
/// come from TextKit and use the same font metrics as the renderer.
struct ReaderPageTypography {
    var font: UIFont
    var titleFont: UIFont
    var lineSpacing: CGFloat
    var letterSpacing: CGFloat
    var paragraphSpacing: CGFloat
    var firstLineIndent: CGFloat
    var titleSpacing: CGFloat
    var contentWidth: CGFloat
    var contentHeight: CGFloat
}

enum ReaderPageLayoutEngine {
    /// The floating reader toolbar is drawn over the page. Every surface
    /// (native scroll, SwiftUI paged, page-curl) must reserve the same top
    /// inset so the first line is neither hidden by the toolbar nor placed at
    /// a different height when the user switches modes.
    static let defaultTopInset: CGFloat = 56

    static func minimumTopInset(pagePadding: CGFloat) -> CGFloat {
        max(pagePadding + 8, defaultTopInset)
    }

    /// SwiftUI Text has no first-line-only indent.  Prefixing ideographic
    /// spaces is deterministic, keeps wrapped lines flush, and lets TextKit
    /// measure exactly the string SwiftUI will draw.  Scroll mode keeps using
    /// `firstLineHeadIndent`, which resolves to the same visual width for the
    /// default 38pt / 19pt pairing (two full-width spaces).
    static func displayText(_ text: String, fontSize: CGFloat, indent: CGFloat) -> String {
        guard indent > 0, fontSize > 0 else { return text }
        let spaces = Int((indent / fontSize).rounded())
        guard spaces > 0 else { return text }
        return String(repeating: "\u{3000}", count: spaces) + text
    }

    static func measureHeight(
        _ text: String,
        typography: ReaderPageTypography,
        font: UIFont? = nil
    ) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let metrics = lineMetrics(text: text, typography: typography, font: font ?? typography.font)
        return metrics.reduce(CGFloat.zero) { $0 + $1.height }
    }

    /// Split a paragraph at real line boundaries so every returned chunk can
    /// be drawn on one non-scrollable page.  The first chunk may be shorter
    /// than the rest when the page already contains a title or the tail of a
    /// previous paragraph.
    static func split(
        _ text: String,
        firstPageHeight: CGFloat,
        fullPageHeight: CGFloat,
        typography: ReaderPageTypography
    ) -> [(text: String, height: CGFloat)] {
        guard !text.isEmpty else { return [] }
        let metrics = lineMetrics(text: text, typography: typography, font: typography.font)
        guard !metrics.isEmpty else { return [(text, 0)] }

        let string = text as NSString
        var result: [(String, CGFloat)] = []
        var chunkStart = 0
        var currentHeight: CGFloat = 0
        var limit = max(firstPageHeight, metrics[0].height)

        for metric in metrics {
            if currentHeight > 0, currentHeight + metric.height > limit + 0.5 {
                let length = metric.range.location - chunkStart
                if length > 0 {
                    // The last line of a chunk is never followed by another
                    // line, and SwiftUI does not apply `lineSpacing` after the
                    // final line. Reporting the raw accumulator would overstate
                    // the drawn height by one line gap and waste page budget.
                    let drawnHeight = max(currentHeight - typography.lineSpacing, 0)
                    result.append((
                        string.substring(with: NSRange(location: chunkStart, length: length)),
                        drawnHeight
                    ))
                }
                chunkStart = metric.range.location
                currentHeight = 0
                limit = max(fullPageHeight, metric.height)
            }
            currentHeight += metric.height
        }

        if chunkStart < string.length {
            result.append((string.substring(from: chunkStart), currentHeight))
        }
        return result
    }

    private struct LineMetric {
        let range: NSRange
        let height: CGFloat
    }

    private static func lineMetrics(
        text: String,
        typography: ReaderPageTypography,
        font: UIFont
    ) -> [LineMetric] {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = typography.lineSpacing
        style.lineBreakMode = .byWordWrapping
        style.alignment = .natural
        let storage = NSTextStorage(
            string: text,
            attributes: [
                .font: font,
                .kern: typography.letterSpacing,
                .paragraphStyle: style
            ]
        )
        let layout = NSLayoutManager()
        let container = NSTextContainer(
            size: CGSize(width: max(typography.contentWidth, 1), height: .greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)

        var metrics: [LineMetric] = []
        var glyphIndex = 0
        while glyphIndex < layout.numberOfGlyphs {
            var lineGlyphRange = NSRange(location: 0, length: 0)
            let rect = layout.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphRange)
            guard lineGlyphRange.length > 0 else { break }
            let charRange = layout.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            let isLastLine = NSMaxRange(lineGlyphRange) >= layout.numberOfGlyphs
            metrics.append(
                LineMetric(
                    range: charRange,
                    height: rect.height + (isLastLine ? 0 : typography.lineSpacing)
                )
            )
            glyphIndex = NSMaxRange(lineGlyphRange)
        }
        return metrics
    }
}
