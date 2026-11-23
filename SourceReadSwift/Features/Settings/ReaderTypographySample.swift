import SwiftUI
import UIKit

/// SwiftUI Text does not support justification; use the same paragraph inputs as the paged reader.
struct ReaderTypographySample: UIViewRepresentable {
    struct Layout {
        var alignment: ReaderTextAlignment
        var lineSpacing: Double
        var letterSpacing: Double
        var paragraphSpacing: Double
        var paragraphIndent: Double
    }

    static let defaultSampleText = "雨停之后，窗上的水痕还在。顾清寒轻声道：「此去经年。」【纸间示范】\n灯下有一点余温，刚好够读完这一页。"

    let font: UIFont
    var boldFont: UIFont? = nil
    let ink: UIColor
    let layout: Layout
    var highlightRules: [ReaderHighlightRule] = []
    @AppStorage("reader.bodyUnderline") var bodyUnderline = false
    var isNight: Bool = false
    var sampleText: String = ReaderTypographySample.defaultSampleText

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 6
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = layout.alignment.nsTextAlignment
        paragraph.lineSpacing = min(max(layout.lineSpacing, 0), 40)
        paragraph.paragraphSpacing = min(max(layout.paragraphSpacing, 0), 60)
        paragraph.firstLineHeadIndent = min(max(layout.paragraphIndent, 0), 100)
        paragraph.lineBreakStrategy = layout.alignment.compressesPunctuation ? .pushOut : []
        let resolvedBoldFont = boldFont
            ?? font.fontDescriptor.withSymbolicTraits(.traitBold).map { UIFont(descriptor: $0, size: font.pointSize) }
            ?? UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        label.attributedText = ReaderHighlightMatcher.uiKitAttributedString(
            for: sampleText,
            rules: highlightRules,
            baseFont: font,
            boldFont: resolvedBoldFont,
            baseInk: ink,
            paragraphStyle: paragraph,
            letterSpacing: layout.letterSpacing,
            isNight: isNight, underline: bodyUnderline
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}
