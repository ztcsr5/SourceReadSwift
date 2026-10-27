import Foundation

/// Stable identity of one paginated page across page-model rebuilds.
///
/// `ReaderPageBlock.id` is the index inside the current window array. It moves
/// whenever a neighbouring chapter is prefetched or evicted above the reader,
/// so it must never be used to remember what the user is looking at. The
/// chapter-local ordinal plus the first paragraph stays stable while the
/// chapter content and typography are unchanged.
struct ReaderPageIdentity: Equatable, Hashable {
    let chapterIndex: Int
    let pageOrdinal: Int
    let firstParagraphIndex: Int
    let isPlaceholder: Bool

    init(page: ReaderPageBlock) {
        chapterIndex = page.chapterIndex
        pageOrdinal = page.pageOrdinal
        firstParagraphIndex = page.firstParagraphIndex ?? -1
        isPlaceholder = page.isPlaceholder
    }

    init(chapterIndex: Int, pageOrdinal: Int, firstParagraphIndex: Int, isPlaceholder: Bool) {
        self.chapterIndex = chapterIndex
        self.pageOrdinal = pageOrdinal
        self.firstParagraphIndex = firstParagraphIndex
        self.isPlaceholder = isPlaceholder
    }

    var key: String {
        "\(isPlaceholder ? "p" : "b")-\(chapterIndex)-\(pageOrdinal)-\(firstParagraphIndex)"
    }

    static func firstIndex(of key: String, in pages: [ReaderPageBlock]) -> Int? {
        pages.firstIndex { ReaderPageIdentity(page: $0).key == key }
    }
}

/// Pure page-cursor restoration used by every paged reading surface.
///
/// The old implementation fell back to the previous array index whenever the
/// anchor could not be matched. After a backward prefetch inserted chapters
/// above the reader, that index pointed into a completely different chapter,
/// which is the reported “读第五章却跳回第二章” bug. This resolver has one
/// hard rule: when the anchor chapter is present, never return a page from an
/// earlier chapter.
enum ReaderPageRestoration {
    static func index(
        anchor: ReaderChapterPosition?,
        in blocks: [ReaderPageBlock],
        fallbackIndex: Int
    ) -> Int {
        guard !blocks.isEmpty else { return 0 }
        let fallback = min(max(fallbackIndex, 0), blocks.count - 1)
        guard let anchor else { return fallback }

        // Exact continuation page: same chapter, same chapter-local ordinal,
        // same first paragraph. This keeps a page inside a long paragraph when
        // an unrelated chapter is inserted above it.
        if let ordinal = anchor.pageOrdinal,
           let exact = blocks.firstIndex(where: {
               !$0.isPlaceholder
                   && $0.chapterIndex == anchor.chapterIndex
                   && $0.pageOrdinal == ordinal
                   && $0.firstParagraphIndex == anchor.paragraphIndex
           }) {
            return exact
        }

        // Repaginated chapter: choose the page whose paragraph range contains
        // the anchor. This must be the last page whose first paragraph is
        // <= the anchor, not the first page that starts after it.
        if let sameChapter = pageContaining(
            chapter: anchor.chapterIndex,
            paragraph: anchor.paragraphIndex,
            in: blocks
        ) {
            return sameChapter
        }

        // The anchor chapter is no longer in the live window (it was trimmed
        // while a prefetch was in flight). Move forward only: a backward jump
        // is always more destructive than landing on the next loaded page.
        if let forward = blocks.firstIndex(where: {
            !$0.isPlaceholder && $0.chapterIndex >= anchor.chapterIndex
        }) {
            return forward
        }
        if let forwardPlaceholder = blocks.firstIndex(where: {
            $0.isPlaceholder && $0.chapterIndex >= anchor.chapterIndex
        }) {
            return forwardPlaceholder
        }
        return blocks.count - 1
    }

    /// Last page in `chapter` whose first paragraph is at or before
    /// `paragraph`. Returns the chapter's first page when the anchor sits
    /// before every paragraph (for example the chapter title page).
    static func pageContaining(
        chapter: Int,
        paragraph: Int,
        in blocks: [ReaderPageBlock]
    ) -> Int? {
        var firstInChapter: Int?
        var candidate: Int?
        for (index, block) in blocks.enumerated() {
            guard !block.isPlaceholder, block.chapterIndex == chapter else { continue }
            if firstInChapter == nil { firstInChapter = index }
            let first = block.firstParagraphIndex ?? 0
            if first <= paragraph {
                candidate = index
            } else {
                break
            }
        }
        return candidate ?? firstInChapter
    }
}
