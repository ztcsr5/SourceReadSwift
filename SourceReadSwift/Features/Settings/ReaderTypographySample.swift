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

    let font: UIFont
    let ink: UIColor
    let layout: Layout

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 5
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
        label.attributedText = NSAttributedString(
            string: "雨停之后，窗上的水痕还在。她把纸翻过去，读到一行没做标记的句子。\n灯下有一点余温，刚好够读完这一页。",
            attributes: [.font: font, .foregroundColor: ink,
                         .kern: min(max(layout.letterSpacing, 0), 10), .paragraphStyle: paragraph])
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}
