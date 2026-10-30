import CoreGraphics
import Foundation
import UIKit

/// Immutable snapshot of every reader setting the paginator reads.
///
/// Pagination is a pure function of (chapter text, typography, geometry,
/// image policy). Capturing those values lets a worker thread measure a
/// chapter without touching `@AppStorage` or any other main-actor state.
/// `ReaderPageTypography` carries `UIFont`, which is documented as safe to
/// read from any thread but is not marked `Sendable`; the snapshot is
/// immutable after construction, so the unchecked conformance is sound.
struct ReaderChapterPaginationContext: @unchecked Sendable {
    let typography: ReaderPageTypography
    let titleTypography: ReaderPageTypography
    let chromeLayout: ReaderPageChromeLayout
    let imageStyle: ReaderImageStyle
    let viewportHeight: CGFloat
    let pagePadding: Double
    let footerHeight: Double
    let traditionalChinese: Bool
}

/// Cuts one chapter into fixed pages.
///
/// This used to live inside `ReaderView.appendPages` and ran on the main
/// actor. On a local import the paragraphs are already in memory, yet the
/// warmup measured one chapter per runloop turn: the first swipe past the
/// synchronously measured neighbours landed on a chapter that was still being
/// cut and showed its placeholder for a beat. Moving the cut here lets the
/// reader fan out three chapters at a time on the cooperative pool and keep
/// the main thread free for the gesture.
enum ReaderChapterPaginator {
    static func paginate(
        chapterIndex: Int,
        title: String,
        paragraphs: [String],
        context: ReaderChapterPaginationContext
    ) -> [ReaderPageBlock] {
        if !paragraphs.contains(where: { ReaderImageSizingPolicy.imageURL(in: $0.trimmingCharacters(in: .whitespacesAndNewlines)) != nil }) {
            return ReaderTextPagePaginator.paginate(chapterIndex: chapterIndex, title: title, paragraphs: paragraphs, context: context)
        }
        let typography = context.typography
        let titleTypography = context.titleTypography
        var pages: [ReaderPageBlock] = []
        var currentEntries: [ReaderPageEntry] = []
        var pageOrdinal = 0
        let transformedTitle = ReaderTextTransform.displayText(
            title,
            traditionalChinese: context.traditionalChinese
        )
        // 页眉模式：章节名画在页眉带，正文第一页从与后续页完全相同的位置开始，
        // 不再给标题预留 40~50pt 的正文高度。只有「正文大标题」模式保留旧行为。
        var currentHeight: CGFloat = 0
        var currentIncludesTitle = false
        if context.chromeLayout == .inline {
            currentHeight = ReaderPageLayoutEngine.measureHeight(
                transformedTitle,
                typography: titleTypography,
                font: typography.titleFont,
                alignment: .natural
            ) + typography.titleSpacing
            currentIncludesTitle = true
        }

        func flush() {
            pages.append(
                ReaderPageBlock(
                    id: pages.count,
                    includesTitle: currentIncludesTitle,
                    paragraphs: currentEntries,
                    chapterIndex: chapterIndex,
                    chapterTitle: transformedTitle,
                    pageOrdinal: pageOrdinal
                )
            )
            pageOrdinal += 1
            currentEntries = []
            currentHeight = 0
            currentIncludesTitle = false
        }

        for (index, paragraph) in paragraphs.enumerated() {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if ReaderImageSizingPolicy.imageURL(in: trimmed) != nil {
                // `ReaderIllustrationView` also draws the caption row and its
                // vertical padding. Reserving only the bitmap height let a
                // text-plus-image page overflow and clip the last line.
                let captionBudget = ReaderImageSizingPolicy.pagedCaptionHeight
                let imageHeight = min(
                    ReaderImageSizingPolicy.maximumHeight(
                        for: context.imageStyle,
                        viewportHeight: context.viewportHeight,
                        pagePadding: context.pagePadding,
                        footerHeight: context.footerHeight
                    ),
                    max(typography.contentHeight - captionBudget, 1)
                )
                let cardHeight = imageHeight + captionBudget
                if context.imageStyle.reservesWholePage {
                    if currentIncludesTitle || !currentEntries.isEmpty {
                        flush()
                    }
                    currentEntries.append(ReaderPageEntry(
                        index: index,
                        text: paragraph,
                        chapterIndex: chapterIndex
                    ))
                    currentHeight = cardHeight
                    flush()
                } else {
                    let spacing = currentEntries.isEmpty ? 0 : typography.paragraphSpacing
                    if !currentEntries.isEmpty && currentHeight + spacing + cardHeight > typography.contentHeight {
                        flush()
                    }
                    let spacingAfterFlush = currentEntries.isEmpty ? 0 : typography.paragraphSpacing
                    currentEntries.append(ReaderPageEntry(
                        index: index,
                        text: paragraph,
                        chapterIndex: chapterIndex
                    ))
                    currentHeight += spacingAfterFlush + cardHeight
                    if currentHeight >= typography.contentHeight {
                        flush()
                    }
                }
                continue
            }

            // The stored page text includes the first-line indent so the paged
            // surface and TextKit measure exactly the same string. Continuation
            // chunks start at a line boundary and therefore carry no indent.
            let transformedParagraph = ReaderTextTransform.displayText(
                paragraph,
                traditionalChinese: context.traditionalChinese
            )
            let display = ReaderPageLayoutEngine.displayText(
                transformedParagraph,
                fontSize: typography.font.pointSize,
                indent: typography.firstLineIndent
            )
            // One TextKit pass per paragraph: measure once, then cut with the
            // metrics we already paid for. Re-measuring the paragraph inside
            // `split` and every chunk after it was the bulk of the chapter
            // boundary hitch (5 layouts for a paragraph spanning 3 pages).
            let paragraphMetrics = ReaderPageLayoutEngine.metrics(for: display, typography: typography)
            let wholeHeight = ReaderPageLayoutEngine.totalHeight(of: paragraphMetrics)
            let spacing = currentEntries.isEmpty ? 0 : typography.paragraphSpacing

            if currentHeight + spacing + wholeHeight <= typography.contentHeight {
                currentEntries.append(ReaderPageEntry(
                    index: index,
                    text: display,
                    chapterIndex: chapterIndex
                ))
                currentHeight += spacing + wholeHeight
                continue
            }

            let minLineHeight = ceil(typography.font.lineHeight) + 2
            let remaining = typography.contentHeight - currentHeight - spacing
            if !currentEntries.isEmpty, remaining < minLineHeight {
                flush()
            } else if currentEntries.isEmpty, currentIncludesTitle,
                      remaining < minLineHeight {
                flush()
            }

            let available: CGFloat
            if currentEntries.isEmpty {
                available = max(typography.contentHeight - currentHeight, minLineHeight)
            } else {
                available = max(
                    typography.contentHeight - currentHeight - typography.paragraphSpacing,
                    minLineHeight
                )
            }
            let chunks = ReaderPageLayoutEngine.split(
                display,
                metrics: paragraphMetrics,
                firstPageHeight: available,
                fullPageHeight: typography.contentHeight,
                typography: typography
            )
            var sourceOffset = 0
            for (chunkIndex, chunk) in chunks.enumerated() {
                let spacingBefore = currentEntries.isEmpty
                    ? 0
                    : (chunkIndex == 0 ? typography.paragraphSpacing : 0)
                if !currentEntries.isEmpty,
                   currentHeight + spacingBefore + chunk.height > typography.contentHeight {
                    flush()
                }
                let spacingAfterFlush = currentEntries.isEmpty
                    ? 0
                    : (chunkIndex == 0 ? typography.paragraphSpacing : 0)
                currentEntries.append(
                    ReaderPageEntry(
                        index: index,
                        text: chunk.text,
                        chunkIndex: chunkIndex,
                        chapterIndex: chapterIndex,
                        sourceUTF16Offset: sourceOffset
                    )
                )
                sourceOffset += chunk.text.utf16.count
                currentHeight += spacingAfterFlush + chunk.height
                if chunkIndex < chunks.count - 1 {
                    flush()
                }
            }
        }

        if currentIncludesTitle || !currentEntries.isEmpty {
            flush()
        }
        return pages
    }
}
