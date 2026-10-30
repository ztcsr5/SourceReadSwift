import UIKit

/// Text pages are cut by TextKit from the SAME attributed document that is
/// rendered. No sums of estimated per-paragraph heights or fixed safety buffer.
/// Each invocation owns its TextKit stack; no displayed text view is shared.
enum ReaderTextPagePaginator {
    static func paginate(
        chapterIndex: Int,
        title: String,
        paragraphs: [String],
        context: ReaderChapterPaginationContext
    ) -> [ReaderPageBlock] {
        let typography = context.typography
        let title = ReaderTextTransform.displayText(title, traditionalChinese: context.traditionalChinese)
        let display = paragraphs.map {
            ReaderPageLayoutEngine.displayText(
                ReaderTextTransform.displayText($0, traditionalChinese: context.traditionalChinese),
                fontSize: typography.font.pointSize,
                indent: typography.firstLineIndent
            )
        }
        let inlineTitle = context.chromeLayout == .inline && !title.isEmpty ? title : nil
        let style = ReaderPageTextBuilder.layoutStyle(typography)
        let document = ReaderPageTextBuilder.make(
            title: inlineTitle,
            paragraphs: display.map { .init(text: $0, isContinuation: false, isHighlighted: false) },
            style: style
        )
        guard document.length > 0 else { return [] }

        let titleRange = NSRange(location: 0, length: inlineTitle?.utf16.count ?? 0)
        var cursor = inlineTitle.map { $0.utf16.count + 1 } ?? 0
        var sourceRanges: [NSRange] = []
        for (index, text) in display.enumerated() {
            sourceRanges.append(NSRange(location: cursor, length: text.utf16.count))
            cursor += text.utf16.count + (index < display.count - 1 ? 1 : 0)
        }

        let storage = NSTextStorage(attributedString: document)
        let manager = NSLayoutManager()
        manager.allowsNonContiguousLayout = false
        storage.addLayoutManager(manager)
        var characterEnd = 0
        var pages: [ReaderPageBlock] = []
        var paragraphCursor = 0
        var chunks = Array(repeating: 0, count: display.count)

        // Shaping can change the glyph count as layout advances (notably RTL
        // ligatures). Completion belongs to immutable source UTF16 characters,
        // never to a glyph count captured before layout.
        while characterEnd < document.length {
            let container = NSTextContainer(size: CGSize(
                width: max(typography.contentWidth, 1),
                height: max(typography.contentHeight, typography.font.lineHeight)
            ))
            container.lineFragmentPadding = 0
            container.lineBreakMode = .byWordWrapping
            manager.addTextContainer(container)
            if manager.textContainers.count == 1 {
                manager.ensureGlyphs(forCharacterRange: NSRange(location: 0, length: document.length))
            }
            manager.ensureLayout(for: container)
            let glyphs = manager.glyphRange(for: container)
            let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let pageEnd = NSMaxRange(characters)
            // The UI guarantees enough height for a title/body line. Invalid
            // smaller external contexts must not spin forever.
            guard pageEnd > characterEnd else { break }
            characterEnd = pageEnd
            var entries: [ReaderPageEntry] = []
            while paragraphCursor < sourceRanges.count {
                let range = sourceRanges[paragraphCursor]
                if range.location >= pageEnd { break }
                let overlap = NSIntersectionRange(range, characters)
                if overlap.length > 0 || (range.length == 0 && range.location >= characters.location) {
                    let offset = max(overlap.location - range.location, 0)
                    let text = (display[paragraphCursor] as NSString).substring(with: NSRange(location: offset, length: overlap.length))
                    entries.append(ReaderPageEntry(
                        index: paragraphCursor,
                        text: text,
                        chunkIndex: chunks[paragraphCursor],
                        chapterIndex: chapterIndex,
                        sourceUTF16Offset: offset
                    ))
                    chunks[paragraphCursor] += 1
                }
                if NSMaxRange(range) <= pageEnd { paragraphCursor += 1 } else { break }
            }
            let titlePart = NSIntersectionRange(titleRange, characters)
            let hasTitle = titlePart.length > 0
            if !entries.isEmpty || hasTitle {
                pages.append(ReaderPageBlock(
                    id: pages.count,
                    includesTitle: hasTitle,
                    paragraphs: entries,
                    chapterIndex: chapterIndex,
                    chapterTitle: title,
                    pageOrdinal: pages.count,
                    inlineTitleText: hasTitle ? (title as NSString).substring(with: titlePart) : nil
                ))
            }
        }
        return pages
    }
}
