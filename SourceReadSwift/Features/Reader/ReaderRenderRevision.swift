import Foundation

/// Location identity is for navigation; a render revision describes the bytes
/// and layout that a host actually displays. Never use one in place of the other.
enum ReaderRenderRevision {
    static func chapter(title: String, paragraphs: [String]) -> String {
        var hash = Hasher()
        hash.combine(title)
        hash.combine(paragraphs)
        return String(hash.finalize())
    }

    static func page(_ page: ReaderPageBlock) -> String {
        var hash = Hasher()
        hash.combine(page.chapterTitle)
        hash.combine(page.inlineTitleText)
        hash.combine(page.includesTitle)
        hash.combine(page.isPlaceholder)
        hash.combine(page.placeholderDirection)
        for entry in page.paragraphs {
            hash.combine(entry.index)
            hash.combine(entry.text)
            hash.combine(entry.chunkIndex)
            hash.combine(entry.sourceUTF16Offset)
        }
        return String(hash.finalize())
    }
}
