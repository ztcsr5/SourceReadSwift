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
    var state: LoadState = .ready

    /// Every construction site (fresh network load, disk cache, local import,
    /// window seed) goes through the sanitizer. Old on-disk chapter caches
    /// therefore get the duplicate-heading fix without a cache migration.
    init(chapterIndex: Int, title: String, paragraphs: [String], state: LoadState = .ready) {
        let normalized = ChapterTextSanitizer.normalize(
            title: title,
            paragraphs: paragraphs,
            fallbackTitle: "第 \(chapterIndex + 1) 章"
        )
        self.chapterIndex = chapterIndex
        self.title = normalized.title
        self.paragraphs = normalized.paragraphs
        self.state = state
    }

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

/// Chapter-local pagination cached under one layout signature.
///
/// The window used to re-measure every paragraph of every loaded chapter each
/// time a prefetched neighbour arrived. Chapter pagination is immutable while
/// typography, viewport and image style stay the same, so the reader keeps each
/// chapter's page array here and only renumbers ids when assembling the window.
struct ReaderChapterPageCacheEntry: Equatable {
    let layoutSignature: String
    let contentSignature: String
    let blocks: [ReaderPageBlock]
}

struct ReaderChapterPosition: Equatable {
    let chapterIndex: Int
    let paragraphIndex: Int
    /// Paged modes use a chapter-local page ordinal to keep the exact
    /// continuation page when another chapter is prefetched above it.
    let pageOrdinal: Int?

    init(chapterIndex: Int, paragraphIndex: Int, pageOrdinal: Int? = nil) {
        self.chapterIndex = chapterIndex
        self.paragraphIndex = paragraphIndex
        self.pageOrdinal = pageOrdinal
    }
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

    /// Last readable chapter index plus one.
    ///
    /// The live table of contents wins over `totalChapters`. The bookshelf
    /// stores a chapter count from the last successful refresh; when the
    /// source removes or reorders chapters that number can be larger than the
    /// live TOC, and a window that trusts it keeps requesting chapters that do
    /// not exist. That looked like a reader that refused to continue: every
    /// boundary request failed silently. When the TOC is unavailable, fall
    /// back to the persisted count.
    static func upperBound(
        totalChapters: Int?,
        chapterIndices: [Int],
        fallback: Int
    ) -> Int {
        let fallbackValue = max(fallback, 1)
        if let highest = chapterIndices.max() {
            return max(highest + 1, fallbackValue)
        }
        if let totalChapters, totalChapters > 0 {
            return max(totalChapters, fallbackValue)
        }
        return fallbackValue
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
            .filter { $0 != current && !loaded.contains($0) }
            .sorted { lhs, rhs in
                let leftDistance = abs(lhs - current)
                let rightDistance = abs(rhs - current)
                if leftDistance != rightDistance { return leftDistance < rightDistance }
                if (lhs >= current) != (rhs >= current) { return lhs >= current }
                return lhs < rhs
            }
    }

    /// Chapters the live window must keep in memory. Loading chapters are
    /// retained so a boundary request cannot be evicted before its content
    /// arrives; the cursor chapter is always kept even when a caller passes a
    /// radius of zero.
    static func retainedIndices(
        around current: Int,
        radius: Int,
        lowerBound: Int,
        upperBound: Int,
        loading: Set<Int>
    ) -> Set<Int> {
        var result = Set(indices(
            around: current,
            radius: radius,
            lowerBound: lowerBound,
            upperBound: upperBound
        ))
        result.formUnion(loading.filter { $0 >= lowerBound && $0 < upperBound })
        if current >= lowerBound, current < upperBound {
            result.insert(current)
        }
        return result
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

    /// Paragraph sentinel used when a placeholder is replaced by the real
    /// chapter. Forward travel lands on the first page; backward travel lands
    /// on the last page. `Int.max` is the established chapter-end sentinel
    /// consumed by the page resolver.
    static func restoreParagraphIndex(
        chapterIndex: Int,
        currentChapterIndex: Int,
        placeholderDirection: Int
    ) -> Int {
        if placeholderDirection < 0 { return Int.max }
        if placeholderDirection > 0 { return 0 }
        return chapterIndex < currentChapterIndex ? Int.max : 0
    }
}

/// Automatic retry backoff for a chapter that failed while the reader sits on
/// its boundary. Three automatic retries cover a transient source timeout
/// without hammering it; after that the placeholder keeps a manual retry
/// button and the automatic one waits for it.
enum ReaderChapterRetryPolicy {
    static let maximumAutomaticAttempts = 3

    static func delay(afterAttempt attempt: Int) -> TimeInterval? {
        guard attempt >= 0, attempt < maximumAutomaticAttempts else { return nil }
        switch attempt {
        case 0: return 2
        case 1: return 5
        default: return 10
        }
    }
}

/// Where a table-of-contents, bookmark or chapter-slider jump should land.
enum ReaderChapterJumpDisposition: Equatable {
    /// The chapter is already live in the window; jump without any load.
    case activate
    /// The chapter belongs to the book but is not loaded yet. Load it into the
    /// window and keep the reader surface alive instead of recreating it.
    case loadIntoWindow
    /// The index is outside the table of contents.
    case outOfRange
}

/// A jump the reader is waiting for while its chapter downloads.
struct ReaderPendingChapterJump: Equatable {
    let chapterIndex: Int
    var paragraphIndex: Int
    var startAtEnd: Bool = false
}

extension ReaderChapterWindowPolicy {
    /// A TOC/bookmark jump must never fall back to the owner callback just
    /// because the chapter is outside the prefetched window: that callback
    /// rebuilds the whole reader (new `.id`, new web view, full HTML
    /// injection) and is what made chapter switching feel like a cold open.
    static func jumpDisposition(
        target: Int,
        loadedIndices: Set<Int>,
        upperBound: Int
    ) -> ReaderChapterJumpDisposition {
        if loadedIndices.contains(target) { return .activate }
        guard target >= 0, target < upperBound else { return .outOfRange }
        return .loadIntoWindow
    }
}
