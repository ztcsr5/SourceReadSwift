import Foundation

/// One chapter held by the reader's live window. The window keeps the current
/// chapter plus the chapters on both sides so scroll, cover and page-curl can
/// cross a chapter boundary without tearing down the reader view.
struct ReaderChapterSection: Identifiable, Equatable {
    enum LoadState: Equatable {
        case ready
        case loading
        case failed(String)
    }

    let chapterIndex: Int
    var title: String
    var paragraphs: [String]
    var state: LoadState

    var id: Int { chapterIndex }
    var isReady: Bool { state == .ready }
    var isLoading: Bool { state == .loading }
}

/// A chapter start/count pair used to build the flat paragraph space that the
/// scroll surface and the paged position mapping share.
struct ReaderChapterSlice: Equatable {
    let chapterIndex: Int
    let paragraphCount: Int
}

struct ReaderChapterPosition: Equatable {
    let chapterIndex: Int
    let paragraphIndex: Int
}

/// Pure window math for continuous cross-chapter reading.
///
/// The reader used to append chapters only in the forward direction and only
/// in scroll mode. Keeping the window and flat-index rules here makes the
/// forward/backward handoff testable and keeps the three reading surfaces on
/// one contract.
enum ReaderChapterWindowPolicy {
    /// The window always keeps at least one chapter on each side. A preload
    /// setting of zero turns extra prefetching off; it must not remove the
    /// ability to continue into the next chapter.
    static let minimumRadius = 1

    static func radius(forPreloadCount count: Int) -> Int {
        max(ReaderPreloadPolicy.clamp(count), minimumRadius)
    }

    /// Inclusive chapter indices around `current`, clamped to the book.
    static func indices(
        around current: Int,
        radius: Int,
        lowerBound: Int,
        upperBound: Int
    ) -> [Int] {
        guard upperBound > lowerBound else { return [] }
        let safeCurrent = min(max(current, lowerBound), upperBound - 1)
        let safeRadius = max(radius, 0)
        let lower = max(lowerBound, safeCurrent - safeRadius)
        let upper = min(upperBound - 1, safeCurrent + safeRadius)
        guard lower <= upper else { return [] }
        return Array(lower...upper)
    }

    /// Nearest-first load order. At equal distance the forward chapter wins:
    /// reading progress is overwhelmingly forward.
    static func prefetchOrder(
        current: Int,
        radius: Int,
        lowerBound: Int,
        upperBound: Int,
        loaded: Set<Int>
    ) -> [Int] {
        indices(around: current, radius: radius, lowerBound: lowerBound, upperBound: upperBound)
            .filter { !loaded.contains($0) }
            .sorted { lhs, rhs in
                let leftDistance = abs(lhs - current)
                let rightDistance = abs(rhs - current)
                if leftDistance != rightDistance { return leftDistance < rightDistance }
                if (lhs >= current) != (rhs >= current) { return lhs >= current }
                return lhs < rhs
            }
    }

    /// First chapter outside the window in `direction` that still needs a
    /// load. Returns nil when the book edge or a fully loaded window is hit.
    static func nextMissingIndex(
        direction: Int,
        current: Int,
        lowerBound: Int,
        upperBound: Int,
        loaded: Set<Int>
    ) -> Int? {
        guard upperBound > lowerBound, direction != 0 else { return nil }
        var index = current + (direction > 0 ? 1 : -1)
        while index >= lowerBound, index < upperBound {
            if !loaded.contains(index) { return index }
            index += direction > 0 ? 1 : -1
        }
        return nil
    }

    struct LayoutSlot: Equatable {
        let chapterIndex: Int
        let start: Int
        let count: Int
        /// Index of the one-paragraph chapter divider. The first chapter has
        /// no divider because the native surface draws its title itself.
        let headerIndex: Int?
    }

    struct Layout: Equatable {
        let slots: [LayoutSlot]

        var totalCount: Int {
            guard let last = slots.last else { return 0 }
            return last.start + last.count
        }

        func slot(forChapter chapterIndex: Int) -> LayoutSlot? {
            slots.first { $0.chapterIndex == chapterIndex }
        }

        func paragraphStart(chapterIndex: Int) -> Int? {
            slot(forChapter: chapterIndex)?.start
        }

        /// Flat index for a chapter-local paragraph. Paragraph values are
        /// clamped so a persisted Int.max ("start at the end") is safe.
        func flatIndex(chapterIndex: Int, paragraphIndex: Int) -> Int? {
            guard let slot = slot(forChapter: chapterIndex) else { return nil }
            guard slot.count > 0 else { return slot.start }
            let local = min(max(paragraphIndex, 0), slot.count - 1)
            return slot.start + local
        }
    }

    /// Builds the flat paragraph space used by both reading surfaces.
    ///
    /// The first section occupies `count` paragraphs. Every later section is
    /// preceded by one divider paragraph, matching `scrollModeParagraphs` and
    /// the chapter title pages of the paged model. Keeping the same rule in
    /// both places is what makes a mode switch land on the same text.
    static func layout(_ slices: [ReaderChapterSlice]) -> Layout {
        var slots: [LayoutSlot] = []
        var cursor = 0
        for (offset, slice) in slices.enumerated() {
            let headerIndex: Int? = offset == 0 ? nil : cursor
            let start = cursor + (offset == 0 ? 0 : 1)
            slots.append(
                LayoutSlot(
                    chapterIndex: slice.chapterIndex,
                    start: start,
                    count: max(slice.paragraphCount, 0),
                    headerIndex: headerIndex
                )
            )
            cursor = start + max(slice.paragraphCount, 0)
        }
        return Layout(slots: slots)
    }

    static func layout(_ sections: [ReaderChapterSection]) -> Layout {
        layout(sections.map { ReaderChapterSlice(chapterIndex: $0.chapterIndex, paragraphCount: $0.paragraphs.count) })
    }

    /// Resolve a flat paragraph index back to the owning chapter. A divider
    /// index maps to the previous chapter's last paragraph so scroll progress
    /// never jumps to an unrelated chapter while a divider crosses the
    /// viewport.
    static func resolvedPosition(flatIndex: Int, layout: Layout) -> ReaderChapterPosition? {
        guard let first = layout.slots.first else { return nil }
        let index = max(flatIndex, 0)
        var previous: LayoutSlot?

        for slot in layout.slots {
            guard slot.count > 0 else {
                previous = slot
                continue
            }
            if index < slot.start {
                if let previous, previous.count > 0 {
                    return ReaderChapterPosition(
                        chapterIndex: previous.chapterIndex,
                        paragraphIndex: previous.count - 1
                    )
                }
                return ReaderChapterPosition(chapterIndex: slot.chapterIndex, paragraphIndex: 0)
            }
            if index < slot.start + slot.count {
                return ReaderChapterPosition(
                    chapterIndex: slot.chapterIndex,
                    paragraphIndex: index - slot.start
                )
            }
            previous = slot
        }

        if let last = layout.slots.last(where: { $0.count > 0 }) {
            return ReaderChapterPosition(chapterIndex: last.chapterIndex, paragraphIndex: last.count - 1)
        }
        return ReaderChapterPosition(chapterIndex: first.chapterIndex, paragraphIndex: 0)
    }

    /// Flat-index displacement of one anchor chapter between two window
    /// layouts. Inserting chapters above the viewport moves every existing
    /// paragraph down by this amount; the native surface compensates with it.
    static func flatShift(
        oldSlices: [ReaderChapterSlice],
        newSlices: [ReaderChapterSlice],
        anchorChapterIndex: Int
    ) -> Int {
        let oldStart = layout(oldSlices).paragraphStart(chapterIndex: anchorChapterIndex) ?? 0
        let newStart = layout(newSlices).paragraphStart(chapterIndex: anchorChapterIndex) ?? 0
        return newStart - oldStart
    }

    /// Page-curl/cover transition target: the first ready page at or after
    /// the requested chapter, else the nearest following chapter's first page.
    static func firstPageIndex(chapterIndex: Int, in pages: [(chapterIndex: Int, isPlaceholder: Bool)]) -> Int? {
        if let index = pages.firstIndex(where: { $0.chapterIndex == chapterIndex && !$0.isPlaceholder }) {
            return index
        }
        if let index = pages.firstIndex(where: { $0.chapterIndex >= chapterIndex && !$0.isPlaceholder }) {
            return index
        }
        return pages.indices.last
    }

    static func lastPageIndex(chapterIndex: Int, in pages: [(chapterIndex: Int, isPlaceholder: Bool)]) -> Int? {
        let matches = pages.indices.filter { pages[$0].chapterIndex == chapterIndex && !pages[$0].isPlaceholder }
        return matches.last
    }
}