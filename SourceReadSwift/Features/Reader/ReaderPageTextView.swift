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

    static func make(title: String?, paragraphs: [Paragraph], style: Style) -> NSAttributedString {
        let output = NSMutableAttributedString()

        if let title, !title.isEmpty {
            let titleStyle = NSMutableParagraphStyle()
            titleStyle.lineSpacing = 0
            titleStyle.paragraphSpacing = style.titleSpacing
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
            paragraphStyle.paragraphSpacing = index == paragraphs.count - 1
                ? 0
                : (paragraph.isContinuation ? 0 : style.paragraphSpacing)
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
            output.append(NSAttributedString(string: paragraph.text, attributes: attributes))
            if index != paragraphs.count - 1 {
                output.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }

        return output
    }
}

/// TextKit surface for one paginated page.
///
/// SwiftUI `Text` cannot justify CJK paragraphs: it only offers leading,
/// center, trailing and natural alignment. A non-scrolling `UITextView` keeps
/// the same TextKit metrics the paginator measured, justifies full lines and
/// lets the paragraph carry its own indent without an extra head indent.
struct ReaderPageTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    let isSelectable: Bool

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.contentInset = .zero
        // iOS 16 still applies the safe-area/content inset to a text view
        // inside a UIPageViewController child; leaving it on shifts the first
        // line down and makes a full page look clipped.
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

    func updateUIView(_ view: UITextView, context: Context) {
        view.attributedText = attributedText
        view.isSelectable = isSelectable
        // With selection off the text view must not swallow page-turn taps.
        // With selection on the long-press selection UI is the explicit user
        // choice, so interaction stays enabled.
        view.isUserInteractionEnabled = isSelectable
    }

    /// The page owns a fixed frame from `pageSurface`. Returning that proposal
    /// keeps UITextView's content-sized intrinsic height out of SwiftUI's
    /// layout pass, which is the iOS 16 path that used to widen or lengthen a
    /// page before the first layout.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}
