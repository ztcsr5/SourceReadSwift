import CoreGraphics
import Foundation

/// Pure decisions shared by the three paged reader surfaces.
///
/// The reader used to keep these rules inline in SwiftUI/UIKit callbacks,
/// which made boundary handling untestable and allowed a mismatch between the
/// visible page and `pagedPageIndex`.  Keeping them here gives scroll, cover,
/// page-curl and the page splitter one deterministic contract.

enum ReaderCoverSwipeDecision: Equatable {
    case next
    case previous
    case cancel
}

enum ReaderCoverSwipePolicy {
    /// Decide whether a cover-mode drag should commit a page turn.
    ///
    /// A short flick is honoured through `predictedEndTranslation`; a slow drag
    /// must cross a share of the container width.  Vertical gestures and
    /// boundary swipes always cancel so the page can spring back.
    static func decision(
        translation: CGSize,
        predictedEndTranslation: CGSize,
        containerWidth: CGFloat,
        pageIndex: Int,
        pageCount: Int,
        minimumDistance: CGFloat = 36,
        axisBias: CGFloat = 1.15
    ) -> ReaderCoverSwipeDecision {
        guard pageCount > 0 else { return .cancel }
        guard abs(translation.width) >= minimumDistance else { return .cancel }
        guard abs(translation.width) > abs(translation.height) * axisBias else { return .cancel }

        let width = max(containerWidth, 1)
        let threshold = max(width * 0.18, minimumDistance)
        // Only trust the prediction when it agrees with the drag direction.
        let predicted = predictedEndTranslation.width
        let effective: CGFloat
        if predicted != 0, predicted * translation.width > 0, abs(predicted) > abs(translation.width) {
            effective = predicted
        } else {
            effective = translation.width
        }
        guard abs(effective) >= threshold else { return .cancel }

        if effective < 0 {
            guard pageIndex < pageCount - 1 else { return .cancel }
            return .next
        }
        guard pageIndex > 0 else { return .cancel }
        return .previous
    }
}

enum ReaderPageCurlSyncDecision: Equatable {
    case none
    case reloadCurrentPage
    case move(to: Int)
}

enum ReaderPageCurlSyncPolicy {
    /// UIPageViewController owns its own gesture.  SwiftUI must not animate a
    /// page change while the user is dragging, otherwise the two animations
    /// fight and the visible page no longer matches the binding.
    static func decision(
        displayedIndex: Int?,
        desiredIndex: Int,
        pageCount: Int,
        contentRevisionChanged: Bool,
        isUserInteracting: Bool
    ) -> ReaderPageCurlSyncDecision {
        guard pageCount > 0 else { return .none }
        let clamped = min(max(desiredIndex, 0), pageCount - 1)
        guard !isUserInteracting else { return .none }
        if contentRevisionChanged { return .reloadCurrentPage }
        guard let displayedIndex else { return .move(to: clamped) }
        guard displayedIndex != clamped else { return .none }
        return .move(to: clamped)
    }
}

enum ReaderPageTextSplitter {
    private static let breakCharacters: Set<Character> = [
        "。", "！", "？", "；", "…", "，", "、", "：",
        ".", "!", "?", ";", ",", ":", " ", "\n", "\t"
    ]

    /// Split an over-long paragraph on a natural punctuation boundary.
    ///
    /// The pagination model measures whole paragraphs, so a single 5,000
    /// character paragraph used to render as one overflowing page.  Chunks
    /// stay within `maximumUTF16Length` (plus at most one grapheme) and prefer
    /// the last punctuation mark inside the window.  Joining the result always
    /// reconstructs the original text.
    static func split(_ text: String, maximumUTF16Length: Int) -> [String] {
        let limit = max(maximumUTF16Length, 32)
        guard text.utf16.count > limit else { return [text] }

        var chunks: [String] = []
        var current = String()
        var currentLength = 0

        for character in text {
            let addition = String(character).utf16.count
            if currentLength + addition > limit, !current.isEmpty {
                if let breakIndex = current.lastIndex(where: { breakCharacters.contains($0) }) {
                    let head = String(current[...breakIndex])
                    if head.utf16.count >= limit / 3, head.utf16.count < current.utf16.count {
                        chunks.append(head)
                        current = String(current[current.index(after: breakIndex)...])
                        currentLength = current.utf16.count
                    } else {
                        chunks.append(current)
                        current.removeAll(keepingCapacity: true)
                        currentLength = 0
                    }
                } else {
                    chunks.append(current)
                    current.removeAll(keepingCapacity: true)
                    currentLength = 0
                }
            }
            current.append(character)
            currentLength += addition
        }

        if !current.isEmpty { chunks.append(current) }
        return chunks.isEmpty ? [text] : chunks
    }
}

enum ReaderPagedNavigationPolicy {
    static func clampedPageIndex(_ rawIndex: Int, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        return min(max(rawIndex, 0), pageCount - 1)
    }

    /// One page model is shared by all three paged modes.  Clamp both the page
    /// cursor and the paragraph cursor whenever the model is rebuilt so a
    /// typography change can never leave the reader on a deleted page.
    static func clampedTargets(
        pageIndex: Int,
        paragraphIndex: Int,
        pageCount: Int,
        paragraphCount: Int
    ) -> (page: Int, paragraph: Int) {
        let page = clampedPageIndex(pageIndex, pageCount: pageCount)
        let paragraph = paragraphCount > 0
            ? min(max(paragraphIndex, 0), paragraphCount - 1)
            : 0
        return (page, paragraph)
    }

    /// Convert the live paragraph cursor to the page that owns it.  Used by
    /// mode switches and by speech/TTS callbacks.
    static func page(
        containingParagraph paragraphIndex: Int,
        pageFirstParagraphs: [Int]
    ) -> Int {
        guard !pageFirstParagraphs.isEmpty else { return 0 }
        let target = max(paragraphIndex, 0)
        var lower = 0
        var upper = pageFirstParagraphs.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if pageFirstParagraphs[middle] < target {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        if lower < pageFirstParagraphs.count, pageFirstParagraphs[lower] == target {
            return lower
        }
        return max(lower - 1, 0)
    }
}

/// Continuous-scroll page stepping used by the reader tap zones.
///
/// The scroll surface used to ignore every tap zone except "menu", even
/// though the default left/right zones are page turns, so the whole screen
/// looked dead in the default reading mode.  One tap now moves by one
/// viewport minus a small overlap (a line is never skipped) and reports when
/// the reader already sits on the first/last line so the caller can hand over
/// to the neighbouring chapter.
enum ReaderPageStepPolicy {
    static let overlapRatio: CGFloat = 0.12

    static func targetOffsetY(
        currentOffsetY: CGFloat,
        boundsHeight: CGFloat,
        contentSizeHeight: CGFloat,
        adjustedTop: CGFloat = 0,
        adjustedBottom: CGFloat = 0,
        direction: Int
    ) -> CGFloat {
        let minimumY = -adjustedTop
        let maximumY = max(minimumY, contentSizeHeight - boundsHeight + adjustedBottom)
        guard boundsHeight > 0, direction != 0 else {
            return min(max(currentOffsetY, minimumY), maximumY)
        }
        let step = max(boundsHeight * (1 - overlapRatio), 1)
        let desired = currentOffsetY + (direction > 0 ? step : -step)
        return min(max(desired, minimumY), maximumY)
    }

    static func reachedBoundary(currentOffsetY: CGFloat, targetOffsetY: CGFloat) -> Bool {
        abs(targetOffsetY - currentOffsetY) < 0.5
    }
}
