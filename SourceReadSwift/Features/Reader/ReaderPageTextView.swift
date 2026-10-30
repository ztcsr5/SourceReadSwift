import SwiftUI
import UIKit

/// Builds the attributed string for one paginated reader page.
///
/// Pagination stores the first-line indent as ideographic spaces inside the
/// paragraph (see `ReaderPageLayoutEngine.displayText`), so the paragraph
/// style must not add `firstLineHeadIndent` again. The builder only applies
/// justification: full lines reach both edges, the last line stays flush left
/// because text is not stretched after its final glyph.
enum ReaderPageTextBuilder {
    struct Style {
        let bodyFont: UIFont
        let titleFont: UIFont
        let textColor: UIColor
        let highlightColor: UIColor
        let lineSpacing: CGFloat
        let letterSpacing: CGFloat
        let paragraphSpacing: CGFloat
        let titleSpacing: CGFloat
    }

    struct Paragraph {
        let text: String
        let isContinuation: Bool
        let isHighlighted: Bool
    }

    static func layoutStyle(_ typography: ReaderPageTypography, textColor: UIColor = .label, highlightColor: UIColor = .clear) -> Style {
        Style(bodyFont: typography.font, titleFont: typography.titleFont,
              textColor: textColor, highlightColor: highlightColor,
              lineSpacing: typography.lineSpacing, letterSpacing: typography.letterSpacing,
              paragraphSpacing: typography.paragraphSpacing, titleSpacing: typography.titleSpacing)
    }

    static func make(title: String?, paragraphs: [Paragraph], style: Style) -> NSAttributedString {
        let output = NSMutableAttributedString()

        if let title, !title.isEmpty {
            let titleStyle = NSMutableParagraphStyle()
            titleStyle.lineSpacing = 0
            titleStyle.paragraphSpacing = style.titleSpacing
            titleStyle.lineBreakStrategy = ReaderPageLayoutEngine.lineBreakStrategy
            titleStyle.alignment = .natural
            output.append(NSAttributedString(
                string: title + "\n",
                attributes: [
                    .font: style.titleFont,
                    .foregroundColor: style.textColor,
                    .paragraphStyle: titleStyle
                ]
            ))
        }

        for (index, paragraph) in paragraphs.enumerated() {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = style.lineSpacing
            // Paragraph spacing belongs to the newline that terminates this
            // paragraph. It must therefore be decided by the NEXT paragraph:
            // a split continuation is glued to this chunk, and a continuation
            // followed by a new paragraph starts a new visual block. The
            // paginator already adds spacing only before chunkIndex == 0;
            // testing `paragraph.isContinuation` here measured a different
            // document than the one TextKit rendered.
            let effectiveSpacing = max(0, style.paragraphSpacing - style.lineSpacing)
            paragraphStyle.paragraphSpacing = index == paragraphs.count - 1
                ? 0
                : (paragraphs[index + 1].isContinuation ? 0 : effectiveSpacing)
            paragraphStyle.lineBreakStrategy = ReaderPageLayoutEngine.lineBreakStrategy
            paragraphStyle.alignment = .justified
            // The indent is already part of `paragraph.text`; adding it here
            // would double the first line and break pagination measurement.
            paragraphStyle.firstLineHeadIndent = 0
            paragraphStyle.headIndent = 0

            var attributes: [NSAttributedString.Key: Any] = [
                .font: style.bodyFont,
                .foregroundColor: style.textColor,
                .kern: style.letterSpacing,
                .paragraphStyle: paragraphStyle
            ]
            if paragraph.isHighlighted {
                attributes[.backgroundColor] = style.highlightColor
            }
            let piece = NSMutableAttributedString(
                string: paragraph.text,
                attributes: attributes
            )
            // Keep the renderer's glyph advances identical to the paginator's
            // (see `ReaderPageLayoutEngine.lineMetrics`): iOS 16 does not trim
            // the trailing blank of full-width punctuation on its own.
            ReaderCJKPunctuationCompression.apply(
                to: piece,
                font: style.bodyFont,
                baseKern: style.letterSpacing
            )
            output.append(piece)
            if index != paragraphs.count - 1 {
                output.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }

        return output
    }
}

/// Everything one page's attributed string is built from, captured on the
/// main thread. Building the string touches only Core Text/UIKit value types,
/// so the prewarm pass can run it on a background queue.
struct ReaderPageTextSpec {
    let title: String?
    let paragraphs: [ReaderPageTextBuilder.Paragraph]
    let style: ReaderPageTextBuilder.Style

    var attributedString: NSAttributedString {
        ReaderPageTextBuilder.make(title: title, paragraphs: paragraphs, style: style)
    }
}

/// TextKit 1 surface that finishes glyph layout as soon as it owns a size.
///
/// A plain `UITextView` defers glyph generation until its first draw. In the
/// page-curl reader that draw happens on the first frame of the swipe, so a
/// page whose attributed string was already built still looked like it was
/// "loading" for a beat. `ensureLayout` inside `layoutSubviews` moves that
/// work onto the off-screen prewarm pass (`PageCurlReaderView.prewarm` sets a
/// frame and calls `layoutIfNeeded`), which runs before the finger reaches
/// the page.
final class ReaderPrepaginatedTextView: UITextView {
    private var needsGlyphLayout = false

    static func makePageSurface() -> ReaderPrepaginatedTextView {
        let view = ReaderPrepaginatedTextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.contentInset = .zero
        view.contentInsetAdjustmentBehavior = .never
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.widthTracksTextView = true
        view.textContainer.maximumNumberOfLines = 0
        view.textContainer.lineBreakMode = .byWordWrapping
        view.adjustsFontForContentSizeCategory = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    /// Assigning `attributedText` invalidates TextKit and schedules a layout
    /// pass; the glyph run itself waits for the first draw. Flag the page so
    /// the next `layoutSubviews` can force it.
    func setPage(_ text: NSAttributedString) {
        needsGlyphLayout = true
        attributedText = text
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard needsGlyphLayout else { return }
        let width = bounds.width - textContainerInset.left - textContainerInset.right
        // Before the hosting view gets its frame the width is zero; keep the
        // flag and let the prewarm layout pass (which sets the frame) finish.
        guard width > 1 else { return }
        needsGlyphLayout = false
        textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
    }
}

/// TextKit surface for one paginated page.
///
/// SwiftUI `Text` cannot justify CJK paragraphs: it only offers leading,
/// center, trailing and natural alignment. A non-scrolling `UITextView` keeps
/// the same TextKit metrics the paginator measured, justifies full lines and
/// lets the paragraph carry its own indent without an extra head indent.
struct ReaderPageTextView: UIViewRepresentable {
    /// Built lazily. `readerPage(for:)` is evaluated while
    /// `PageCurlReaderView` answers a swipe gesture, so building the attributed
    /// page there (paragraph styles + CJK punctuation compression for every
    /// paragraph) put a full TextKit pass on the gesture's main thread. The
    /// provider runs when the view is actually loaded, which the page-curl
    /// prewarm now does ahead of the swipe.
    let attributedTextProvider: () -> NSAttributedString
    /// Stable key for the rendered page: page identity + typography revision +
    /// speech highlight. Compared instead of `isEqual` on the full attributed
    /// string, which walked every character on each layout pass and was a
    /// hidden per-frame cost during curls.
    let contentKey: String
    let isSelectable: Bool

    final class Coordinator {
        var appliedKey = ""
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ReaderPrepaginatedTextView {
        ReaderPrepaginatedTextView.makePageSurface()
    }

    func updateUIView(_ view: ReaderPrepaginatedTextView, context: Context) {
        // SwiftUI can call this for a layout-only change. Reassigning
        // `attributedText` tears down and rebuilds the TextKit layout, so only
        // do it when the page revision actually changed.
        if context.coordinator.appliedKey != contentKey {
            context.coordinator.appliedKey = contentKey
            // Lays the page out now instead of on the first drawn frame.
            view.setPage(attributedTextProvider())
        }
        if view.isSelectable != isSelectable {
            view.isSelectable = isSelectable
            // With selection off the text view must not swallow page-turn taps.
            // With selection on the long-press selection UI is the explicit user
            // choice, so interaction stays enabled.
            view.isUserInteractionEnabled = isSelectable
        }
    }

    /// The page owns a fixed frame from `pageSurface`. Returning that proposal
    /// keeps UITextView's content-sized intrinsic height out of SwiftUI's
    /// layout pass, which is the iOS 16 path that used to widen or lengthen a
    /// page before the first layout.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ReaderPrepaginatedTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}
