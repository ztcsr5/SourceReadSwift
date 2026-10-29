import Foundation
import UIKit

/// Emulates the CJK punctuation trimming ("标点挤压") that CoreText applies
/// automatically from iOS 17 onwards.
///
/// iOS 16 keeps the full em advance for `，` `。` `；` … even when the glyph
/// only paints half of it. A justified line that ends with one of those
/// characters therefore stops half a character short of the right margin and
/// the paragraph shows a wide gap after every comma — the two symptoms that
/// make the same chapter look "loose" on iOS 16 and tight on iOS 17.
///
/// CoreText expresses the trim as a negative `.kern` on the punctuation glyph,
/// so the same attribute is applied here and shared by pagination and drawing.
/// Measurement and rendering must pass the same font and base kern, otherwise a
/// page measures one line and draws another.
enum ReaderCJKPunctuationCompression {
    /// Fraction of one em removed after the glyph. Values follow the Chinese
    /// typesetting convention: 点号 occupy half a character, closing quotes and
    /// brackets half a character, 叹号/问号 a quarter.
    private static let trailingTrim: [Character: CGFloat] = [
        "，": 0.5, "。": 0.5, "、": 0.5, "；": 0.5, "：": 0.5,
        "！": 0.25, "？": 0.25,
        "”": 0.5, "’": 0.5, "）": 0.5, "》": 0.5, "」": 0.5, "』": 0.5,
        "】": 0.5, "〕": 0.5, "〉": 0.5
    ]

    /// Every scalar that carries a trim, as a set so the scan can jump
    /// straight to the next mark instead of walking the whole page.
    private static let punctuationSet: CharacterSet = CharacterSet(
        charactersIn: String(trailingTrim.keys)
    )

    static func apply(
        to text: NSMutableAttributedString,
        font: UIFont,
        baseKern: CGFloat = 0
    ) {
        let length = text.length
        guard length > 0, font.pointSize > 0 else { return }
        let string = text.string as NSString
        let em = font.pointSize
        // `rangeOfCharacter` is a framework-side memchr-style scan, so this
        // loop only visits punctuation. Walking every CJK glyph and building a
        // `Character` per index was measurable inside both page rendering and
        // pagination measurement for every page of the book.
        var search = NSRange(location: 0, length: length)
        while search.length > 0 {
            let hit = string.rangeOfCharacter(from: punctuationSet, options: [], range: search)
            guard hit.location != NSNotFound else { return }
            let unit = string.character(at: hit.location)
            // All keys are BMP scalars; a stray surrogate half cannot match.
            if let scalar = Unicode.Scalar(unit), let trim = trailingTrim[Character(scalar)] {
                text.addAttribute(
                    .kern,
                    value: baseKern - trim * em,
                    range: NSRange(location: hit.location, length: 1)
                )
            }
            let next = NSMaxRange(hit)
            search = NSRange(location: next, length: length - next)
        }
    }
}
