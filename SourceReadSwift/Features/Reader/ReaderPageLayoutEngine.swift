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
    /// CJK line-breaking policy shared by the paginator and the renderer.
    ///
    /// With the default `.standard` strategy TextKit is happy to start a line
    /// with `。`, `，`, `）` or `」`; in Chinese typesetting that is the most
    /// visible "typeset by an engineer" tell. `.pushOut` lets the preceding
    /// glyph hang slightly past the margin instead of pushing the punctuation
    /// to the next line. The paginator and the page renderer must use the same
    /// strategy, otherwise a page measures one line and draws another.
    static let lineBreakStrategy: NSParagraphStyle.LineBreakStrategy = .pushOut

    /// The top inset for reader surfaces. Setting this to 0 eliminates artificial
    /// blank gaps at the top of the reading page while keeping content aligned
    /// with the configured page padding.
    static let defaultTopInset: CGFloat = 0

    static var safeAreaTopInset: CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.top ?? 0
    }

    static func minimumTopInset(pagePadding: CGFloat, safeTop: CGFloat? = nil) -> CGFloat {
        let safe = safeTop ?? safeAreaTopInset
        if safe >= 44 {
            // 刘海屏 / 灵动岛机型 (iPhone X ~ 16)：紧凑避让顶部挖孔，正文紧随页眉展开，拒绝大面积空白
            return safe + 4
        } else if safe > 0 {
            // 普通状态栏机型 (iPhone SE、iPad)
            return safe + 8
        } else {
            // 单元测试 / 零安全区环境：保持基准值
            return max(pagePadding, 16)
        }
    }

    /// SwiftUI Text has no first-line-only indent.  Prefixing ideographic
    /// spaces is deterministic, keeps wrapped lines flush, and lets TextKit
    /// measure exactly the string SwiftUI will draw.  Scroll mode keeps using
    /// `firstLineHeadIndent`, which resolves to the same visual width for the
    /// default 38pt / 19pt pairing (two full-width spaces).
    static func displayText(_ text: String, fontSize: CGFloat, indent: CGFloat) -> String {
        guard !text.isEmpty, indent > 0, fontSize > 0 else { return text }
        let spaces = Int((indent / fontSize).rounded())
        guard spaces > 0 else { return text }
        return String(repeating: "\u{3000}", count: spaces) + text
    }

    static func measureHeight(
        _ text: String,
        typography: ReaderPageTypography,
        font: UIFont? = nil,
        alignment: NSTextAlignment = .justified
    ) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let metrics = lineMetrics(
            text: text,
            typography: typography,
            font: font ?? typography.font,
            alignment: alignment
        )
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
                    // Re-measure the exact substring instead of adjusting the
                    // accumulator. A chunk's final line does not receive
                    // `lineSpacing`, and re-measuring keeps the reserved height
                    // identical to what the renderer will draw (the whole-text
                    // line metrics only decide where to cut).
                    let chunk = string.substring(with: NSRange(location: chunkStart, length: length))
                    result.append((chunk, measureHeight(chunk, typography: typography)))
                }
                chunkStart = metric.range.location
                currentHeight = 0
                limit = max(fullPageHeight, metric.height)
            }
            currentHeight += metric.height
        }

        if chunkStart < string.length {
            let tail = string.substring(from: chunkStart)
            result.append((tail, measureHeight(tail, typography: typography)))
        }
        return result
    }

    /// The paragraph style used by both measurement and drawing.
    ///
    /// `ReaderPageTextView` draws body paragraphs with `.justified` and titles
    /// with `.natural`; the paginator must pass the same value or it measures
    /// one alignment and the page renders another. Exposed for tests so the
    /// two surfaces cannot drift apart again.
    static func paragraphStyle(alignment: NSTextAlignment = .justified) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        // Keep paragraphStyle.lineSpacing at 0 so lineFragmentRect reports the
        // pure single-line glyph box height; `lineMetrics` adds
        // `typography.lineSpacing` once per inter-line gap to match SwiftUI
        // `.lineSpacing(...)` without double-counting it on every line.
        style.lineSpacing = 0
        style.lineBreakMode = .byWordWrapping
        style.lineBreakStrategy = lineBreakStrategy
        style.alignment = alignment
        return style
    }

    private struct LineMetric {
        let range: NSRange
        let height: CGFloat
    }

    private static func lineMetrics(
        text: String,
        typography: ReaderPageTypography,
        font: UIFont,
        alignment: NSTextAlignment = .justified
    ) -> [LineMetric] {
        let style = paragraphStyle(alignment: alignment)
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
