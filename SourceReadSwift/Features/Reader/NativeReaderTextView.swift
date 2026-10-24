import SwiftUI
import UIKit
import QuartzCore

/// A TextKit-backed reader surface. SwiftUI remains responsible for the
/// surrounding chrome, while UIKit owns the long-form text layout and scroll
/// physics so paragraph updates do not rebuild a LazyVStack every frame.
struct NativeReaderTextView: UIViewRepresentable {
    let title: String
    var subtitle: String? = nil
    let paragraphs: [String]
    /// A caller-provided revision lets the native surface detect edits to a
    /// paragraph in the middle of a long chapter without hashing that chapter
    /// during every SwiftUI body evaluation. It is optional for existing call sites.
    var contentFingerprint: String? = nil
    var isAppendedUpdate: Bool = false
    /// Absolute flat paragraph that must stay under the viewport after a
    /// window rebuild. `layoutAnchorRevision` is monotonic: the native surface
    /// consumes the anchor exactly once per revision, so SwiftUI coalescing
    /// several chapter loads into one update can neither apply a delta twice
    /// nor lose an intermediate prepend.
    var layoutAnchorParagraph: Int? = nil
    var layoutAnchorOldParagraph: Int? = nil
    var layoutAnchorRevision: Int = 0
    var fontFamily: ReaderFontFamily = .system
    let fontSize: Double
    let lineSpacing: Double
    let pagePadding: Double
    let letterSpacing: Double
    let paragraphSpacing: Double
    let paragraphIndent: Double
    let titleSpacing: Double
    let footerHeight: Double
    /// 顶部留白。阅读器传当前 chrome 状态对应的值：浮层可见时给 56pt 让开工具栏，
    /// 自动隐藏后收到 26pt，正文与章标题才会贴到安全区下面，而不是永远悬在半空。
    var topInset: Double? = nil
    let textColor: UIColor
    /// 文字表面自己铺一层主题底色。以前是 `.clear` 交给 SwiftUI 背景，
    /// 一出现布局空档（换章占位、橡皮筋回弹）就露出窗口白底，看着像渲染错误。
    var surfaceColor: UIColor = .clear
    let highlightColor: UIColor
    let currentParagraphIndex: Int
    let scrollTarget: Int?
    let scrollRequestKey: String?
    let animatedScrollDuration: Double
    let textSelectionEnabled: Bool
    var showChapterEndBadge: Bool = false
    var imageStyle: ReaderImageStyle = .standard
    var imageHeaders: [String: String] = [:]
    var imageColumnWidth: CGFloat = 0
    let onVisibleParagraph: (Int) -> Void
    var onNearBottom: (() -> Void)? = nil
    var onReachTop: (() -> Void)? = nil
    var onNearTop: (() -> Void)? = nil
    var onReachBottom: (() -> Void)? = nil
    /// One tap-zone page step in continuous scroll mode. `generation` is
    /// monotonic so the same direction can be requested twice in a row
    /// without SwiftUI diffing the two requests as equal.
    var pageStepDirection: Int = 0
    var pageStepGeneration: Int = 0
    var onPageStepBoundary: ((Int) -> Void)? = nil
    /// 首次「跳到目标段落」真正落到屏幕上之后回调。
    /// 阅读器用它控制首帧透明度：内容没定位到之前先不显示，
    /// 否则用户会先看到第 1 章顶部，再被切成上次读到的位置。
    var onScrollTargetApplied: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onVisibleParagraph: onVisibleParagraph,
            onReachTop: onReachTop,
            onNearTop: onNearTop,
            onReachBottom: onReachBottom,
            onNearBottom: onNearBottom,
            onPageStepBoundary: onPageStepBoundary,
            onScrollTargetApplied: onScrollTargetApplied
        )
    }

    func makeUIView(context: Context) -> UITextView {
        let textView: UITextView
        if #available(iOS 16.0, *) {
            // Explicitly use TextKit 1 (usingTextLayoutManager: false) to guarantee
            // synchronous layout sizing, stable contentSize, and avoid TextKit 2 compatibility
            // layout glitches that cause rubber-band bouncing and main-thread stalls.
            textView = UITextView(usingTextLayoutManager: false)
        } else {
            textView = UITextView(frame: .zero)
        }
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = textSelectionEnabled
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.alwaysBounceVertical = true
        textView.delaysContentTouches = false
        textView.canCancelContentTouches = true
        textView.textContainer.lineFragmentPadding = 0
        textView.contentInsetAdjustmentBehavior = .never
        textView.layoutManager.allowsNonContiguousLayout = false
        textView.decelerationRate = .normal
        textView.setContentHuggingPriority(.defaultLow, for: .vertical)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        context.coordinator.attach(textView)
        context.coordinator.update(
            textView: textView,
            configuration: configuration,
            scrollTarget: scrollTarget,
            scrollRequestKey: scrollRequestKey,
            pageStepDirection: pageStepDirection,
            pageStepGeneration: pageStepGeneration
        )
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.updateCallbacks(
            visibleParagraph: onVisibleParagraph,
            reachTop: onReachTop,
            nearTop: onNearTop,
            reachBottom: onReachBottom,
            nearBottom: onNearBottom,
            pageStepBoundary: onPageStepBoundary,
            scrollTargetApplied: onScrollTargetApplied
        )
        context.coordinator.update(
            textView: textView,
            configuration: configuration,
            scrollTarget: scrollTarget,
            scrollRequestKey: scrollRequestKey,
            pageStepDirection: pageStepDirection,
            pageStepGeneration: pageStepGeneration
        )
        context.coordinator.updateHighlight(currentParagraphIndex, in: textView, color: highlightColor)
        context.coordinator.updateSelection(textSelectionEnabled, in: textView)
    }

    private var configuration: Configuration {
        Configuration(
            title: title,
            subtitle: subtitle,
            paragraphs: paragraphs,
            contentFingerprint: contentFingerprint?.nilIfEmpty
                ?? [title, subtitle ?? "", String(paragraphs.count), String(paragraphs.first?.hashValue ?? 0), String(paragraphs.last?.hashValue ?? 0)].joined(separator: "|"),
            isAppendedUpdate: isAppendedUpdate,
            layoutAnchorParagraph: layoutAnchorParagraph,
            layoutAnchorOldParagraph: layoutAnchorOldParagraph,
            layoutAnchorRevision: layoutAnchorRevision,
            fontFamily: fontFamily,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            pagePadding: pagePadding,
            letterSpacing: letterSpacing,
            paragraphSpacing: paragraphSpacing,
            paragraphIndent: paragraphIndent,
            titleSpacing: titleSpacing,
            footerHeight: footerHeight,
            topInset: topInset,
            textColor: textColor,
            surfaceColor: surfaceColor,
            highlightColor: highlightColor,
            animatedScrollDuration: animatedScrollDuration,
            showChapterEndBadge: showChapterEndBadge,
            imageStyle: imageStyle,
            imageHeaders: imageHeaders,
            imageColumnWidth: imageColumnWidth
        )
    }

    struct Configuration: Equatable {
        let title: String
        let subtitle: String?
        let paragraphs: [String]
        let contentFingerprint: String
        let isAppendedUpdate: Bool
        let layoutAnchorParagraph: Int?
        let layoutAnchorOldParagraph: Int?
        let layoutAnchorRevision: Int
        let fontFamily: ReaderFontFamily
        let fontSize: Double
        let lineSpacing: Double
        let pagePadding: Double
        let letterSpacing: Double
        let paragraphSpacing: Double
        let paragraphIndent: Double
        let titleSpacing: Double
        let footerHeight: Double
        let topInset: Double?
        let textColor: UIColor
        let surfaceColor: UIColor
        let highlightColor: UIColor
        let animatedScrollDuration: Double
        let showChapterEndBadge: Bool
        let imageStyle: ReaderImageStyle
        let imageHeaders: [String: String]
        let imageColumnWidth: CGFloat

        init(
            title: String,
            subtitle: String? = nil,
            paragraphs: [String],
            contentFingerprint: String,
            isAppendedUpdate: Bool = false,
            layoutAnchorParagraph: Int? = nil,
            layoutAnchorOldParagraph: Int? = nil,
            layoutAnchorRevision: Int = 0,
            fontFamily: ReaderFontFamily = .system,
            fontSize: Double,
            lineSpacing: Double,
            pagePadding: Double,
            letterSpacing: Double,
            paragraphSpacing: Double,
            paragraphIndent: Double,
            titleSpacing: Double,
            footerHeight: Double,
            topInset: Double? = nil,
            textColor: UIColor,
            surfaceColor: UIColor = .clear,
            highlightColor: UIColor,
            animatedScrollDuration: Double,
            showChapterEndBadge: Bool = false,
            imageStyle: ReaderImageStyle = .standard,
            imageHeaders: [String: String] = [:],
            imageColumnWidth: CGFloat = 0
        ) {
            self.title = title
            self.subtitle = subtitle
            self.paragraphs = paragraphs
            self.contentFingerprint = contentFingerprint
            self.isAppendedUpdate = isAppendedUpdate
            self.layoutAnchorParagraph = layoutAnchorParagraph
            self.layoutAnchorOldParagraph = layoutAnchorOldParagraph
            self.layoutAnchorRevision = layoutAnchorRevision
            self.fontFamily = fontFamily
            self.fontSize = fontSize
            self.lineSpacing = lineSpacing
            self.pagePadding = pagePadding
            self.letterSpacing = letterSpacing
            self.paragraphSpacing = paragraphSpacing
            self.paragraphIndent = paragraphIndent
            self.titleSpacing = titleSpacing
            self.footerHeight = footerHeight
            self.topInset = topInset
            self.textColor = textColor
            self.surfaceColor = surfaceColor
            self.highlightColor = highlightColor
            self.animatedScrollDuration = animatedScrollDuration
            self.showChapterEndBadge = showChapterEndBadge
            self.imageStyle = imageStyle
            self.imageHeaders = imageHeaders
            self.imageColumnWidth = imageColumnWidth
        }

        struct TextLayoutSignature: Equatable {
            let title: String
            let subtitle: String?
            let contentFingerprint: String
            let fontFamily: ReaderFontFamily
            let fontSize: Double
            let lineSpacing: Double
            let letterSpacing: Double
            let paragraphSpacing: Double
            let paragraphIndent: Double
            let titleSpacing: Double
            let showChapterEndBadge: Bool
            let imageStyle: ReaderImageStyle
            let imageColumnWidth: CGFloat
        }

        struct InsetsSignature: Equatable {
            let pagePadding: Double
            let footerHeight: Double
            let topInset: Double?
        }

        var textLayoutSignature: TextLayoutSignature {
            TextLayoutSignature(
                title: title,
                subtitle: subtitle,
                contentFingerprint: contentFingerprint,
                fontFamily: fontFamily,
                fontSize: fontSize,
                lineSpacing: lineSpacing,
                letterSpacing: letterSpacing,
                paragraphSpacing: paragraphSpacing,
                paragraphIndent: paragraphIndent,
                titleSpacing: titleSpacing,
                showChapterEndBadge: showChapterEndBadge,
                imageStyle: imageStyle,
                imageColumnWidth: imageColumnWidth
            )
        }

        var insetsSignature: InsetsSignature {
            InsetsSignature(pagePadding: pagePadding, footerHeight: footerHeight, topInset: topInset)
        }

        static func == (lhs: Configuration, rhs: Configuration) -> Bool {
            lhs.contentFingerprint == rhs.contentFingerprint
                && lhs.fontFamily == rhs.fontFamily
                && lhs.fontSize == rhs.fontSize
                && lhs.lineSpacing == rhs.lineSpacing
                && lhs.pagePadding == rhs.pagePadding
                && lhs.letterSpacing == rhs.letterSpacing
                && lhs.paragraphSpacing == rhs.paragraphSpacing
                && lhs.paragraphIndent == rhs.paragraphIndent
                && lhs.titleSpacing == rhs.titleSpacing
                && lhs.footerHeight == rhs.footerHeight
                && lhs.topInset == rhs.topInset
                && lhs.textColor.isEqual(rhs.textColor)
                && lhs.surfaceColor.isEqual(rhs.surfaceColor)
                && lhs.highlightColor.isEqual(rhs.highlightColor)
                && lhs.animatedScrollDuration == rhs.animatedScrollDuration
                && lhs.showChapterEndBadge == rhs.showChapterEndBadge
                && lhs.isAppendedUpdate == rhs.isAppendedUpdate
                && lhs.layoutAnchorParagraph == rhs.layoutAnchorParagraph
                && lhs.layoutAnchorOldParagraph == rhs.layoutAnchorOldParagraph
                && lhs.layoutAnchorRevision == rhs.layoutAnchorRevision
                && lhs.imageStyle == rhs.imageStyle
                && lhs.imageHeaders == rhs.imageHeaders
                && abs(lhs.imageColumnWidth - rhs.imageColumnWidth) < 0.5
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIScrollViewDelegate {
        private weak var textView: UITextView?
        private var visibleParagraphCallback: (Int) -> Void
        private var reachTopCallback: (() -> Void)?
        private var nearTopCallback: (() -> Void)?
        private var reachBottomCallback: (() -> Void)?
        private var nearBottomCallback: (() -> Void)?
        private var pageStepBoundaryCallback: ((Int) -> Void)?
        private var scrollTargetAppliedCallback: (() -> Void)?
        private var lastPageStepGeneration = 0
        private var configuration: Configuration?
        private var paragraphRanges: [NSRange] = []
        private var lastHighlightedParagraph = -1
        private var lastHighlightColor: UIColor?
        private var lastScrollRequestKey: String?
        private var lastVisibleParagraph = -1
        private var lastVisibleUpdateAt: CFTimeInterval = 0
        private var lastLayoutAnchorRevision = 0
        private var didConfigureTextView = false
        private var lastSelectionEnabled: Bool?
        private var lastLayoutWidth: CGFloat?
        private var hasAppliedInitialScrollTarget = false
        private var didFireNearBottom = false
        private var didFireNearTop = false
        private var isProgrammaticScrolling = false
        /// 连点翻页时排队。动画进行中再来一下只记方向，不重新算目标。
        private var isPageStepping = false
        private var pendingPageStepDirection = 0
        /// 滑动期间被推迟的整窗重建配置；惯性结束后补做。
        private var deferredConfiguration: Configuration?
        private var illustrationLoadTask: Task<Void, Never>?
        private var illustrationGeneration = 0
        private static let illustrationLoadConcurrency = 4

        init(
            onVisibleParagraph: @escaping (Int) -> Void,
            onReachTop: (() -> Void)? = nil,
            onNearTop: (() -> Void)? = nil,
            onReachBottom: (() -> Void)? = nil,
            onNearBottom: (() -> Void)? = nil,
            onPageStepBoundary: ((Int) -> Void)? = nil,
            onScrollTargetApplied: (() -> Void)? = nil
        ) {
            visibleParagraphCallback = onVisibleParagraph
            reachTopCallback = onReachTop
            nearTopCallback = onNearTop
            reachBottomCallback = onReachBottom
            nearBottomCallback = onNearBottom
            pageStepBoundaryCallback = onPageStepBoundary
            scrollTargetAppliedCallback = onScrollTargetApplied
        }

        func attach(_ textView: UITextView) {
            self.textView = textView
            guard !didConfigureTextView else { return }
            didConfigureTextView = true
            textView.delegate = self
            textView.scrollsToTop = true
        }

        func updateCallbacks(
            visibleParagraph: @escaping (Int) -> Void,
            reachTop: (() -> Void)?,
            nearTop: (() -> Void)?,
            reachBottom: (() -> Void)?,
            nearBottom: (() -> Void)?,
            pageStepBoundary: ((Int) -> Void)?,
            scrollTargetApplied: (() -> Void)? = nil
        ) {
            visibleParagraphCallback = visibleParagraph
            reachTopCallback = reachTop
            nearTopCallback = nearTop
            reachBottomCallback = reachBottom
            nearBottomCallback = nearBottom
            pageStepBoundaryCallback = pageStepBoundary
            if let scrollTargetApplied {
                scrollTargetAppliedCallback = scrollTargetApplied
            }
        }

        func updateSelection(_ enabled: Bool, in textView: UITextView) {
            guard lastSelectionEnabled != enabled else { return }
            lastSelectionEnabled = enabled
            textView.isSelectable = enabled
        }

        func update(
            textView: UITextView,
            configuration newConfiguration: Configuration,
            scrollTarget: Int?,
            scrollRequestKey: String?,
            pageStepDirection: Int,
            pageStepGeneration: Int
        ) {
            attach(textView)
            let previousConfiguration = configuration
            let contentChanged = previousConfiguration?.contentFingerprint != newConfiguration.contentFingerprint
            let textLayoutChanged = previousConfiguration?.textLayoutSignature != newConfiguration.textLayoutSignature
            let insetsChanged = previousConfiguration?.insetsSignature != newConfiguration.insetsSignature
            let textColorChanged = previousConfiguration?.textColor.isEqual(newConfiguration.textColor) != true
            // A chapter is appendable only when this update really added
            // text at the tail of the previous content.  Coalesced
            // prepend+append updates (previous/next prefetch finishing in one
            // run loop) must take the full-rebuild path, otherwise the
            // prepended chapter is silently lost from the text storage.
            let isAppend: Bool = {
                guard newConfiguration.isAppendedUpdate, contentChanged else { return false }
                let previousParagraphs = previousConfiguration?.paragraphs ?? []
                guard newConfiguration.paragraphs.count > previousParagraphs.count else { return false }
                return newConfiguration.paragraphs.prefix(previousParagraphs.count).elementsEqual(previousParagraphs)
            }()
            let anchorRevisionChanged = contentChanged
                && newConfiguration.layoutAnchorRevision != lastLayoutAnchorRevision
            let widthChanged: Bool = {
                guard textView.bounds.width > 1 else { return false }
                guard let lastLayoutWidth else { return true }
                return abs(lastLayoutWidth - textView.bounds.width) > 0.5
            }()
            // 用户正在滑（拖拽 / 惯性）时不立刻整窗重建：一次重建要做
            // ensureLayout + 整窗重排，落在滑动帧里就是那一下卡壳（章界把占位页
            // 换成真实章节时最明显）。先记账，等惯性结束再重建；这期间正文没变，
            // 视觉上不会缺字，也不会跳位置。
            let userIsScrolling = textView.isTracking || textView.isDragging || textView.isDecelerating
            if ReaderRebuildDeferralPolicy.shouldDefer(
                textLayoutChanged: textLayoutChanged,
                isAppend: isAppend,
                hasPreviousConfiguration: previousConfiguration != nil,
                userIsScrolling: userIsScrolling
            ) {
                deferredConfiguration = newConfiguration
                return
            }
            deferredConfiguration = nil
            configuration = newConfiguration

            if textLayoutChanged || widthChanged {
                let previousOffset = textView.contentOffset
                let canFastAppend = isAppend
                    && !anchorRevisionChanged
                    && !widthChanged
                    && previousConfiguration != nil
                    && newConfiguration.fontFamily == previousConfiguration!.fontFamily
                    && newConfiguration.fontSize == previousConfiguration!.fontSize
                    && newConfiguration.lineSpacing == previousConfiguration!.lineSpacing
                    && newConfiguration.letterSpacing == previousConfiguration!.letterSpacing
                    && newConfiguration.paragraphSpacing == previousConfiguration!.paragraphSpacing
                    && newConfiguration.paragraphIndent == previousConfiguration!.paragraphIndent
                    && newConfiguration.titleSpacing == previousConfiguration!.titleSpacing
                    && newConfiguration.paragraphs.count > (previousConfiguration?.paragraphs.count ?? 0)
                    && !paragraphRanges.isEmpty

                if canFastAppend, let prevConfig = previousConfiguration {
                    appendNewParagraphs(from: prevConfig.paragraphs.count, to: newConfiguration, in: textView)
                } else {
                    // Capture the visible character before the layout ranges
                    // change so a non-window content revision (refresh, image
                    // resize) can still keep the exact line under the eye.
                    // Capture before changing the text storage.  A window
                    // mutation shifts paragraphs by a known delta; applying
                    // that delta to this character anchor preserves the exact
                    // line under the eye instead of snapping to the top of the
                    // first visible paragraph.
                    let characterAnchor = !isAppend ? captureScrollAnchor(in: textView) : nil
                    rebuild(textView: textView, configuration: newConfiguration)
                    if textView.bounds.width > 1 {
                        lastLayoutWidth = textView.bounds.width
                    }
                    if anchorRevisionChanged, let anchorParagraph = newConfiguration.layoutAnchorParagraph {
                        // A window mutation changed the flat index space. The
                        // caller resolved the same chapter-local position in
                        // the new layout and supplied the old flat index too.
                        // Shift the captured character anchor by the same flat
                        // delta so a prepended chapter never moves the line
                        // under the eye.
                        lastLayoutAnchorRevision = newConfiguration.layoutAnchorRevision
                        // SwiftUI can coalesce several chapter-window
                        // mutations into one native update. The last
                        // flat index alone then no longer describes the
                        // text the viewport still shows. Recover the
                        // displacement by aligning the old and new
                        // paragraph arrays; fall back to the caller's
                        // flat anchor only when no overlap is provable.
                        let windowShift = previousConfiguration.flatMap { previous in
                            ReaderScrollAnchorPolicy.paragraphShift(
                                old: previous.paragraphs,
                                new: newConfiguration.paragraphs
                            )
                        }
                        if let characterAnchor, let windowShift {
                            restoreScrollAnchor(
                                characterAnchor,
                                paragraphOffset: windowShift,
                                in: textView
                            )
                        } else if let characterAnchor, let oldParagraph = newConfiguration.layoutAnchorOldParagraph {
                            restoreScrollAnchor(
                                characterAnchor,
                                paragraphOffset: anchorParagraph - oldParagraph,
                                in: textView
                            )
                        } else {
                            _ = scrollToParagraph(anchorParagraph, in: textView, animated: false, duration: 0)
                        }
                    } else if let characterAnchor {
                        restoreScrollAnchor(characterAnchor, in: textView)
                    } else if textView.bounds.height > 0 && (!contentChanged || isAppend) {
                        setContentOffsetIfNeeded(previousOffset, in: textView)
                    }
                    // A new chapter needs its initial target; settings/theme
                    // changes or appends preserve the existing offset and request key.
                    let isDifferentChapter = previousConfiguration?.title != newConfiguration.title
                    if isDifferentChapter && !isAppend && !anchorRevisionChanged {
                        lastScrollRequestKey = nil
                        hasAppliedInitialScrollTarget = (scrollTarget == nil || scrollTarget == 0)
                    }
                    if isAppend {
                        didFireNearBottom = false
                    }
                    lastVisibleParagraph = -1
                    lastVisibleUpdateAt = 0
                }
                // Record the revision even when this particular update did
                // not need an anchor (fast append or a content revision with
                // no anchor). Otherwise a later update could mistake an old
                // revision for a fresh one and jump to a stale paragraph.
                if contentChanged {
                    lastLayoutAnchorRevision = newConfiguration.layoutAnchorRevision
                }
            } else {
                if insetsChanged {
                    updateInsets(in: textView, configuration: newConfiguration)
                }
                if textColorChanged {
                    updateBaseTextColor(in: textView, color: newConfiguration.textColor)
                }
            }
            if pageStepGeneration != lastPageStepGeneration {
                lastPageStepGeneration = pageStepGeneration
                if pageStepDirection != 0 {
                    applyPageStep(direction: pageStepDirection, in: textView)
                }
            }
            guard !isAppend else { return }
            guard let scrollTarget,
                  newConfiguration.paragraphs.indices.contains(scrollTarget),
                  scrollRequestKey != lastScrollRequestKey else { return }
            lastScrollRequestKey = scrollRequestKey
            _ = scrollToParagraph(scrollTarget, in: textView, animated: newConfiguration.animatedScrollDuration > 0, duration: newConfiguration.animatedScrollDuration)
        }

        func updateHighlight(_ paragraphIndex: Int, in textView: UITextView, color: UIColor) {
            let colorChanged = lastHighlightColor?.isEqual(color) != true
            guard paragraphIndex != lastHighlightedParagraph || colorChanged else { return }
            let previous = lastHighlightedParagraph
            lastHighlightedParagraph = paragraphIndex
            lastHighlightColor = color
            guard let configuration else { return }
            textView.textStorage.beginEditing()
            if paragraphRanges.indices.contains(previous) {
                textView.textStorage.removeAttribute(.backgroundColor, range: paragraphRanges[previous])
            }
            if paragraphRanges.indices.contains(paragraphIndex) {
                textView.textStorage.addAttribute(.backgroundColor, value: color, range: paragraphRanges[paragraphIndex])
            }
            textView.textStorage.endEditing()
            // Keep the base color alive when a theme changes without forcing a
            // complete rebuild for every speech callback.
            if paragraphIndex < 0, configuration.paragraphs.isEmpty == false {
                textView.textStorage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: textView.textStorage.length))
            }
        }

        private func rebuild(textView: UITextView, configuration: Configuration, restartIllustrationLoads: Bool = true) {
            let result = ReaderNativeTextLayout.makeAttributedText(configuration: configuration)
            paragraphRanges = result.paragraphRanges
            lastHighlightedParagraph = -1
            updateInsets(in: textView, configuration: configuration)
            // Avoid an implicit UIKit text replacement animation when a user
            // changes typography or loads another chapter.
            UIView.performWithoutAnimation {
                textView.attributedText = result.text
                textView.textColor = configuration.textColor
            }
            // Force synchronous layout pass so contentSize.height is accurate and
            // never causes rubber-banding bounces while content remains below.
            textView.layoutManager.ensureLayout(for: textView.textContainer)
            textView.setNeedsLayout()
            textView.layoutIfNeeded()
            if restartIllustrationLoads {
                loadIllustrations(for: configuration, in: textView)
            }
        }

        /// 补做滑动期间被推迟的整窗重建：先抓字符锚点，重建后按锚点复位，
        /// 所以「章界插入/替换」不会把读者眼睛下面那一行挪走。
        /// 只在手彻底停下时执行 —— 手势结束回调本身也在滚动帧里，
        /// 所以调用方会把它再推到下一个 runloop，避免“松手那一下”顿一下。
        private func applyDeferredConfiguration(in textView: UITextView) {
            guard !textView.isTracking, !textView.isDragging, !textView.isDecelerating else { return }
            guard let pending = deferredConfiguration else { return }
            deferredConfiguration = nil
            let anchor = captureScrollAnchor(in: textView)
            configuration = pending
            rebuild(textView: textView, configuration: pending)
            if textView.bounds.width > 1 {
                lastLayoutWidth = textView.bounds.width
            }
            restoreScrollAnchor(anchor, in: textView)
            lastLayoutAnchorRevision = pending.layoutAnchorRevision
            lastVisibleParagraph = -1
            lastVisibleUpdateAt = 0
            didFireNearBottom = false
        }

        private func updateInsets(in textView: UITextView, configuration: Configuration) {
            // 文字视图自己铺主题底色。以前这里是 `.clear`，靠 SwiftUI 背景兜底，
            // 一旦出现布局空档（换章占位、回弹、footer 带）就露出窗口白底。
            if textView.backgroundColor?.isEqual(configuration.surfaceColor) != true {
                textView.backgroundColor = configuration.surfaceColor
            }
            // The representable already lives inside the top safe area. Adding
            // `safeTop` again produced a double inset (a large blank strip above
            // the first line) and disagreed with the paged surface, which starts
            // from the same safe-area origin.
            // 顶留白由调用方按 chrome 显隐给出；没给才退回统一的 56pt 预留。
            let topInset = configuration.topInset.map { CGFloat($0) }
                ?? ReaderPageLayoutEngine.minimumTopInset(pagePadding: CGFloat(configuration.pagePadding))
            let safeBottom = textView.window?.safeAreaInsets.bottom ?? textView.safeAreaInsets.bottom
            let insets = UIEdgeInsets(
                top: topInset,
                left: CGFloat(configuration.pagePadding),
                bottom: CGFloat(configuration.pagePadding + configuration.footerHeight) + safeBottom,
                right: CGFloat(configuration.pagePadding)
            )
            guard textView.textContainerInset.top != insets.top
                    || textView.textContainerInset.left != insets.left
                    || textView.textContainerInset.bottom != insets.bottom
                    || textView.textContainerInset.right != insets.right else { return }
            // 顶留白跟着工具栏显隐变化时补偿 contentOffset，
            // 让眼睛所在的那一行原地不动，而不是整段文字上下蹦。
            let topDelta = insets.top - textView.textContainerInset.top
            let previousOffset = textView.contentOffset
            textView.textContainerInset = insets
            if abs(topDelta) > 0.5, !textView.isTracking, !textView.isDragging, !textView.isDecelerating {
                let minimumY = -textView.adjustedContentInset.top
                let maximumY = max(
                    minimumY,
                    textView.contentSize.height - textView.bounds.height + textView.adjustedContentInset.bottom
                )
                let targetY = min(max(previousOffset.y + topDelta, minimumY), maximumY)
                textView.setContentOffset(CGPoint(x: previousOffset.x, y: targetY), animated: false)
            }
        }

        private func updateBaseTextColor(in textView: UITextView, color: UIColor) {
            guard textView.textStorage.length > 0 else {
                textView.textColor = color
                return
            }
            UIView.performWithoutAnimation {
                let fullRange = NSRange(location: 0, length: textView.textStorage.length)
                var updates: [(NSRange, UIColor)] = []
                textView.textStorage.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
                    let alpha: CGFloat
                    if let existing = value as? UIColor {
                        alpha = existing.resolvedColor(with: textView.traitCollection).cgColor.alpha
                    } else {
                        alpha = 1
                    }
                    updates.append((range, color.withAlphaComponent(alpha)))
                }
                textView.textStorage.beginEditing()
                for (range, updatedColor) in updates {
                    textView.textStorage.addAttribute(.foregroundColor, value: updatedColor, range: range)
                }
                textView.textStorage.endEditing()
                textView.textColor = color
            }
        }

        private func appendNewParagraphs(from oldParagraphCount: Int, to newConfig: Configuration, in textView: UITextView) {
            guard oldParagraphCount < newConfig.paragraphs.count else { return }
            let newParagraphs = Array(newConfig.paragraphs[oldParagraphCount...])
            let chunkResult = ReaderNativeTextLayout.makeAttributedChunk(
                paragraphs: newParagraphs,
                startingLocation: textView.textStorage.length,
                configuration: newConfig
            )
            textView.textStorage.beginEditing()
            textView.textStorage.append(chunkResult.text)
            textView.textStorage.endEditing()
            paragraphRanges.append(contentsOf: chunkResult.paragraphRanges)
            didFireNearBottom = false
            lastVisibleParagraph = -1
            lastVisibleUpdateAt = 0
            loadIllustrations(for: newConfig, in: textView)
        }

        private func loadIllustrations(for config: Configuration, in textView: UITextView) {
            let imageURLs = config.paragraphs.compactMap { ReaderImageSizingPolicy.imageURL(in: $0) }
            guard !imageURLs.isEmpty else {
                illustrationLoadTask?.cancel()
                illustrationLoadTask = nil
                illustrationGeneration += 1
                return
            }

            let missingURLs = imageURLs.filter { RemoteImageLoader.shared.cachedImage(for: $0) == nil }
            guard !missingURLs.isEmpty else {
                illustrationLoadTask?.cancel()
                illustrationLoadTask = nil
                illustrationGeneration += 1
                return
            }

            // A typography change or a new chapter invalidates the previous
            // batch. Keep exactly one loader driving rebuilds for this surface.
            illustrationLoadTask?.cancel()
            illustrationGeneration += 1
            let generation = illustrationGeneration
            let chunks = stride(from: 0, to: missingURLs.count, by: Self.illustrationLoadConcurrency).map {
                Array(missingURLs[$0..<min($0 + Self.illustrationLoadConcurrency, missingURLs.count)])
            }
            let headers = config.imageHeaders

            illustrationLoadTask = Task { @MainActor [weak self, weak textView] in
                guard let self, let textView else { return }
                defer {
                    if self.illustrationGeneration == generation {
                        self.illustrationLoadTask = nil
                    }
                }

                for chunk in chunks {
                    guard !Task.isCancelled, self.illustrationGeneration == generation else { return }
                    var loadedInChunk = false
                    await withTaskGroup(of: (URL, Bool).self) { group in
                        for url in chunk {
                            group.addTask {
                                let image = await RemoteImageLoader.shared.image(for: url, headers: headers)
                                return (url, image != nil)
                            }
                        }
                        for await (_, loaded) in group where loaded {
                            loadedInChunk = true
                        }
                    }

                    guard !Task.isCancelled,
                          self.illustrationGeneration == generation,
                          self.configuration?.contentFingerprint == config.contentFingerprint else { return }
                    guard loadedInChunk else { continue }

                    // Images above the viewport get taller when their real
                    // bitmap replaces the placeholder. Reusing an absolute
                    // contentOffset makes the current paragraph jump; anchor
                    // the top visible character instead and restore it after
                    // the rebuilt layout pass.
                    let anchor = self.captureScrollAnchor(in: textView)
                    self.rebuild(textView: textView, configuration: config, restartIllustrationLoads: false)
                    self.restoreScrollAnchor(anchor, in: textView)
                }
            }
        }

        private func captureScrollAnchor(in textView: UITextView) -> ReaderScrollAnchorPolicy.Anchor? {
            guard !paragraphRanges.isEmpty, textView.bounds.height > 0 else { return nil }
            let length = textView.textStorage.length
            guard length > 0 else { return nil }
            textView.layoutManager.ensureLayout(for: textView.textContainer)

            let contentTop = textView.contentOffset.y + textView.textContainerInset.top
            let probe = CGPoint(x: 0, y: max(0, contentTop))
            var fraction: CGFloat = 0
            let rawIndex = textView.layoutManager.characterIndex(
                for: probe,
                in: textView.textContainer,
                fractionOfDistanceBetweenInsertionPoints: &fraction
            )
            let characterIndex = min(max(rawIndex, 0), length - 1)
            let glyphIndex = textView.layoutManager.glyphIndexForCharacter(at: characterIndex)
            guard glyphIndex < textView.layoutManager.numberOfGlyphs else { return nil }
            let lineRect = textView.layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let progress = lineRect.height > 0
                ? min(max((contentTop - lineRect.minY) / lineRect.height, 0), 1)
                : 0
            return ReaderScrollAnchorPolicy.anchor(
                paragraphRanges: paragraphRanges,
                characterIndex: characterIndex,
                lineProgress: progress
            )
        }

        private func restoreScrollAnchor(
            _ anchor: ReaderScrollAnchorPolicy.Anchor?,
            paragraphOffset: Int = 0,
            in textView: UITextView
        ) {
            guard let anchor else { return }
            let shifted = ReaderScrollAnchorPolicy.Anchor(
                paragraphIndex: max(anchor.paragraphIndex + paragraphOffset, 0),
                characterOffset: anchor.characterOffset,
                lineProgress: anchor.lineProgress
            )
            guard let characterIndex = ReaderScrollAnchorPolicy.characterIndex(for: shifted, in: paragraphRanges),
                  textView.textStorage.length > 0 else { return }
            textView.layoutManager.ensureLayout(for: textView.textContainer)
            let safeIndex = min(max(characterIndex, 0), textView.textStorage.length - 1)
            let glyphIndex = textView.layoutManager.glyphIndexForCharacter(at: safeIndex)
            guard glyphIndex < textView.layoutManager.numberOfGlyphs else { return }
            let lineRect = textView.layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let textY = lineRect.minY + lineRect.height * anchor.lineProgress
            let targetY = ReaderScrollPositionPolicy.targetContentOffsetY(
                textRectMinY: textY,
                textContainerInsetTop: textView.textContainerInset.top,
                boundsHeight: textView.bounds.height,
                contentSizeHeight: textView.contentSize.height,
                adjustedContentInset: textView.adjustedContentInset
            )
            setContentOffsetIfNeeded(CGPoint(x: textView.contentOffset.x, y: targetY), in: textView)
        }

        /// Continuous-scroll tap-zone page turn.  A boundary tap reports back
        /// instead of silently swallowing the gesture, so the reader can move
        /// to the neighbouring chapter.
        private func applyPageStep(direction: Int, in textView: UITextView) {
            guard textView.bounds.height > 0 else { return }
            // 连点排队：上一段翻页动画还在跑时，只记下这一下的方向。
            // 以前每次都拿「飞行中的 contentOffset」重算目标，于是第二下几乎不动、
            // 第三下又跳一大截，看起来就是上下乱跳甚至卡住。
            guard !isPageStepping else {
                pendingPageStepDirection = direction
                return
            }
            let currentY = textView.contentOffset.y
            let targetY = ReaderPageStepPolicy.targetOffsetY(
                currentOffsetY: currentY,
                boundsHeight: textView.bounds.height,
                contentSizeHeight: textView.contentSize.height,
                adjustedTop: textView.adjustedContentInset.top,
                adjustedBottom: textView.adjustedContentInset.bottom,
                direction: direction
            )
            guard !ReaderPageStepPolicy.reachedBoundary(currentOffsetY: currentY, targetOffsetY: targetY) else {
                pageStepBoundaryCallback?(direction)
                return
            }
            isPageStepping = true
            isProgrammaticScrolling = true
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction, .allowAnimatedContent]
            ) {
                textView.setContentOffset(CGPoint(x: 0, y: targetY), animated: false)
            } completion: { [weak self, weak textView] _ in
                guard let self else { return }
                self.isProgrammaticScrolling = false
                self.isPageStepping = false
                if let textView {
                    self.updateVisibleParagraph(in: textView)
                }
                let queued = self.pendingPageStepDirection
                self.pendingPageStepDirection = 0
                if queued != 0, let textView {
                    self.applyPageStep(direction: queued, in: textView)
                }
            }
        }

        private func setContentOffsetIfNeeded(_ offset: CGPoint, in textView: UITextView) {
            let current = textView.contentOffset
            guard abs(current.x - offset.x) > 0.5 || abs(current.y - offset.y) > 0.5 else { return }
            textView.setContentOffset(offset, animated: false)
        }

        @discardableResult
        private func scrollToParagraph(_ index: Int, in textView: UITextView, animated: Bool, duration: Double) -> Bool {
            guard paragraphRanges.indices.contains(index) else { return false }
            // Never fight the user's finger or an in-flight deceleration.
            // A passive visibility callback must not pull the page back to a
            // paragraph boundary while the scroll view is still gliding.
            guard !textView.isTracking && !textView.isDragging && !textView.isDecelerating else { return false }
            if textView.bounds.height <= 0 {
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView else { return }
                    self.scrollToParagraph(index, in: textView, animated: animated, duration: duration)
                }
                return false
            }
            textView.layoutIfNeeded()
            textView.layoutManager.ensureLayout(for: textView.textContainer)
            let range = paragraphRanges[index]
            let glyphRange = textView.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = textView.layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)

            // When animating (such as speech playback or auto-scroll advance):
            // Check if the target paragraph is ALREADY comfortably visible on screen.
            // If it is already visible in the reading area, DO NOT SCROLL to avoid shaking/jitter!
            if animated {
                let glyphTopInViewport = rect.minY - textView.contentOffset.y + textView.textContainerInset.top
                let glyphBottomInViewport = rect.maxY - textView.contentOffset.y + textView.textContainerInset.top
                let safeTop = max(0, textView.textContainerInset.top - 8)
                let safeBottom = textView.bounds.height - textView.textContainerInset.bottom - 32
                if glyphTopInViewport >= safeTop && glyphBottomInViewport <= safeBottom {
                    hasAppliedInitialScrollTarget = true
                    return true
                }
            }

            let targetY: CGFloat
            if animated {
                // Smooth reading follow: position the target paragraph comfortably at ~28% of the viewport height,
                // so the user has visual continuity of surrounding text without violent jumping to the very top.
                let targetViewportY = max(textView.textContainerInset.top + 20, textView.bounds.height * 0.28)
                let idealY = rect.minY + textView.textContainerInset.top - targetViewportY
                let minY = -textView.adjustedContentInset.top
                let maxY = max(minY, textView.contentSize.height - textView.bounds.height + textView.adjustedContentInset.bottom)
                targetY = min(max(idealY, minY), maxY)
            } else {
                targetY = ReaderScrollPositionPolicy.targetContentOffsetY(
                    textRectMinY: rect.minY,
                    textContainerInsetTop: textView.textContainerInset.top,
                    boundsHeight: textView.bounds.height,
                    contentSizeHeight: textView.contentSize.height,
                    adjustedContentInset: textView.adjustedContentInset
                )
            }
            let offset = CGPoint(x: 0, y: targetY)
            let currentOffset = textView.contentOffset
            hasAppliedInitialScrollTarget = true
            guard abs(currentOffset.y - offset.y) > 0.5 else {
                scrollTargetAppliedCallback?()
                return true
            }
            if animated {
                isProgrammaticScrolling = true
                UIView.animate(
                    withDuration: min(max(duration * 0.9, 0.25), 8),
                    delay: 0,
                    options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction, .allowAnimatedContent]
                ) {
                    textView.setContentOffset(offset, animated: false)
                } completion: { [weak self] _ in
                    self?.isProgrammaticScrolling = false
                }
            } else {
                textView.setContentOffset(offset, animated: false)
            }
            scrollTargetAppliedCallback?()
            return true
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // 采样始终打开（开销是几个加法 + 每 240 帧一次 UserDefaults），
            // 这样用户在 设置 → 诊断 里就能读到数字，不必连 Xcode。
            let probeStarted = CACurrentMediaTime()
            defer { ReaderScrollPerfProbe.record(cost: CACurrentMediaTime() - probeStarted) }
            guard let textView = scrollView as? UITextView,
                  let configuration,
                  !paragraphRanges.isEmpty else { return }

            guard !isProgrammaticScrolling else { return }

            guard scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating || hasAppliedInitialScrollTarget else {
                return
            }

            let offsetY = scrollView.contentOffset.y
            let contentHeight = scrollView.contentSize.height
            let visibleBottom = offsetY + scrollView.bounds.height

            if contentHeight > 0 && visibleBottom >= contentHeight - 650 {
                if !didFireNearBottom {
                    didFireNearBottom = true
                    // 不要在 scroll 回调里同步触发章节加载：那一帧里 SwiftUI 会改
                    // 窗口、重建文本，正好撞上正在滑动的这一帧，表现就是卡壳/回弹。
                    DispatchQueue.main.async { [weak self] in
                        self?.nearBottomCallback?()
                    }
                }
            } else if visibleBottom < contentHeight - 900 {
                didFireNearBottom = false
            }

            if contentHeight > 0, offsetY <= 650 {
                if !didFireNearTop {
                    didFireNearTop = true
                    DispatchQueue.main.async { [weak self] in
                        self?.nearTopCallback?()
                    }
                }
            } else if offsetY > 900 {
                didFireNearTop = false
            }

            let now = CACurrentMediaTime()
            guard now - lastVisibleUpdateAt >= 0.25 else { return }
            lastVisibleUpdateAt = now
            updateVisibleParagraph(in: textView)
        }

        private func updateVisibleParagraph(in textView: UITextView) {
            let containerY = max(0, textView.contentOffset.y - textView.textContainerInset.top)
            let visibleRect = CGRect(
                x: 0,
                y: containerY,
                width: max(textView.bounds.width - textView.textContainerInset.left - textView.textContainerInset.right, 1),
                height: textView.bounds.height
            )
            let glyphRange = textView.layoutManager.glyphRange(forBoundingRect: visibleRect, in: textView.textContainer)
            guard glyphRange.length > 0 else { return }
            let visibleCharacterRange = textView.layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let index = ReaderParagraphIndexResolver.firstVisibleIndex(
                in: paragraphRanges,
                visibleRange: visibleCharacterRange
            )
            guard let index, index != lastVisibleParagraph else { return }
            lastVisibleParagraph = index
            visibleParagraphCallback(index)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if let textView = scrollView as? UITextView {
                updateVisibleParagraph(in: textView)
                // 不会继续惯性滑：把推迟的重建推到下一个 runloop，
                // 松手那一帧只做收尾，不在这里排整窗文本。
                if !decelerate {
                    DispatchQueue.main.async { [weak self, weak textView] in
                        guard let self, let textView else { return }
                        self.applyDeferredConfiguration(in: textView)
                    }
                }
            }
            let offsetY = scrollView.contentOffset.y
            let contentHeight = scrollView.contentSize.height
            let visibleBottom = offsetY + scrollView.bounds.height
            // Bottom overscroll triggers append next chapter if needed
            if contentHeight > 0 && visibleBottom >= contentHeight + 40 {
                reachBottomCallback?()
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            if let textView = scrollView as? UITextView {
                updateVisibleParagraph(in: textView)
                // 惯性刚停，这一帧同样不该承担整窗重建。
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView else { return }
                    self.applyDeferredConfiguration(in: textView)
                }
            }
        }
    }
}

/// 滚动采样入口：累加进 `ReaderScrollPerfMeter`（设置页可见），
/// DEBUG 下额外每 300 帧打一行 Console，方便连着 Xcode 时直接看。
enum ReaderScrollPerfProbe {
    #if DEBUG
    private static var frames = 0
    private static var total: Double = 0
    private static var worst: Double = 0
    #endif

    static func record(cost: Double) {
        ReaderScrollPerfMeter.record(cost: cost)
        #if DEBUG
        frames += 1
        total += cost
        worst = max(worst, cost)
        guard frames % 300 == 0 else { return }
        let average = total / Double(frames)
        print(String(format: "[ReaderPerf] scroll×%d avg=%.3fms worst=%.3fms", frames, average * 1000, worst * 1000))
        frames = 0
        total = 0
        worst = 0
        #endif
    }
}

/// Pure scroll-offset math used by the TextKit surface.  Text layout rects are
/// expressed in the text-container coordinate system, while `contentOffset` is
/// expressed in scroll-view coordinates.  `textContainerInset.top` is the
/// visual breathing room between the viewport edge and the first glyph, so it
/// must be subtracted when converting a glyph Y position to a scroll offset.
/// Keeping that conversion here makes paragraph jumps, speech highlighting and
/// automated scrolling use the same coordinate contract.
enum ReaderScrollPositionPolicy {
    static func targetContentOffsetY(
        textRectMinY: CGFloat,
        textContainerInsetTop: CGFloat,
        boundsHeight: CGFloat,
        contentSizeHeight: CGFloat,
        adjustedContentInset: UIEdgeInsets = .zero
    ) -> CGFloat {
        let minimumY = -adjustedContentInset.top
        let maximumY = max(
            minimumY,
            contentSizeHeight - boundsHeight + adjustedContentInset.bottom
        )
        let desiredY = textRectMinY
        return min(max(desiredY, minimumY), maximumY)
    }
}

/// Remembers the character at the top of the viewport across a TextKit
/// rebuild. Paragraph ranges move when an inline attachment changes height,
/// so an absolute contentOffset cannot be reused; the paragraph index plus
/// the offset inside that paragraph survives the rebuild.
enum ReaderScrollAnchorPolicy {
    struct Anchor: Equatable {
        let paragraphIndex: Int
        let characterOffset: Int
        let lineProgress: CGFloat
    }

    static func anchor(
        paragraphRanges: [NSRange],
        characterIndex: Int,
        lineProgress: CGFloat
    ) -> Anchor? {
        guard !paragraphRanges.isEmpty else { return nil }
        var lower = 0
        var upper = paragraphRanges.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if NSMaxRange(paragraphRanges[middle]) <= characterIndex {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        var index = min(lower, paragraphRanges.count - 1)
        // A character index can land on the newline that separates two
        // paragraphs; attribute it to the preceding paragraph in that case.
        if paragraphRanges[index].location > characterIndex, index > 0 {
            index -= 1
        }
        let range = paragraphRanges[index]
        let offset = min(max(characterIndex - range.location, 0), max(range.length - 1, 0))
        return Anchor(
            paragraphIndex: index,
            characterOffset: offset,
            lineProgress: min(max(lineProgress, 0), 1)
        )
    }

    /// Flat-paragraph displacement between two window layouts.
    ///
    /// The chapter window only inserts or removes whole chapter chunks at
    /// its edges. Finding the largest contiguous overlap is therefore
    /// enough to recover the exact shift of the line under the viewport,
    /// even when SwiftUI coalesces a prepend, an append and a trim into a
    /// single native update. Returns nil when the two layouts share no
    /// provable paragraph run (for example an in-place content refresh).
    static func paragraphShift(old: [String], new: [String]) -> Int? {
        guard !old.isEmpty, !new.isEmpty else { return nil }

        func contains(_ haystack: [String], _ needle: [String]) -> Int? {
            guard needle.count <= haystack.count else { return nil }
            guard let first = needle.first else { return nil }
            for start in 0...(haystack.count - needle.count) where haystack[start] == first {
                if haystack[start..<(start + needle.count)].elementsEqual(needle) {
                    return start
                }
            }
            return nil
        }

        if let start = contains(new, old) { return start }
        if let start = contains(old, new) { return -start }

        let maximumOverlap = min(old.count, new.count)
        var bestOverlap = 0
        var bestShift = 0

        // Old suffix -> new prefix (a chapter was removed above or added
        // below the viewport).
        for length in stride(from: maximumOverlap, through: 1, by: -1) {
            if old.suffix(length).elementsEqual(new.prefix(length)) {
                bestOverlap = length
                bestShift = length - old.count
                break
            }
        }

        // Old prefix -> new suffix (a chapter was added above or removed
        // below the viewport).
        for length in stride(from: maximumOverlap, through: 1, by: -1) {
            if old.prefix(length).elementsEqual(new.suffix(length)) {
                let shift = new.count - length
                if length > bestOverlap || (length == bestOverlap && abs(shift) < abs(bestShift)) {
                    bestOverlap = length
                    bestShift = shift
                }
                break
            }
        }

        return bestOverlap > 0 ? bestShift : nil
    }

    static func characterIndex(for anchor: Anchor, in paragraphRanges: [NSRange]) -> Int? {
        guard paragraphRanges.indices.contains(anchor.paragraphIndex) else { return nil }
        let range = paragraphRanges[anchor.paragraphIndex]
        guard range.length > 0 else { return nil }
        return range.location + min(max(anchor.characterOffset, 0), range.length - 1)
    }
}

/// 是否把「整窗文本重建」推迟到滑动结束。
///
/// 重建要 `ensureLayout` + 整窗重排，压在拖拽/惯性帧上就是那一下卡壳
/// （章界把占位页换成真实章节时最明显）。这条判断被抽成纯函数，
/// 才能在 CI 上锁住行为（Coordinator 依赖 UIKit 滚动状态，没法单测）。
enum ReaderRebuildDeferralPolicy {
    static func shouldDefer(
        textLayoutChanged: Bool,
        isAppend: Bool,
        hasPreviousConfiguration: Bool,
        userIsScrolling: Bool
    ) -> Bool {
        // 追加型更新很便宜，照旧即时应用；首次装载没有旧配置可锚定，也不能推迟。
        textLayoutChanged && !isAppend && hasPreviousConfiguration && userIsScrolling
    }
}

/// Resolves the first paragraph intersecting the visible character range in
/// O(log n). Long chapters can contain thousands of paragraph ranges; a full
/// linear scan on every scroll callback needlessly steals main-thread time.
enum ReaderParagraphIndexResolver {
    static func firstVisibleIndex(in ranges: [NSRange], visibleRange: NSRange) -> Int? {
        guard !ranges.isEmpty, visibleRange.length > 0 else { return nil }
        let visibleStart = visibleRange.location
        var lower = 0
        var upper = ranges.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if NSMaxRange(ranges[middle]) <= visibleStart {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        guard ranges.indices.contains(lower) else { return nil }
        if NSIntersectionRange(ranges[lower], visibleRange).length > 0 {
            return lower
        }
        return ranges[lower...].firstIndex { $0.location >= visibleStart }
    }
}

enum ReaderNativeTextLayout {
    struct Result {
        let text: NSAttributedString
        let paragraphRanges: [NSRange]
    }

    static func makeAttributedText(configuration: NativeReaderTextView.Configuration) -> Result {
        let signpost = PerformanceSignpost.begin("reader.textLayout")
        defer { PerformanceSignpost.end("reader.textLayout", id: signpost) }
        let output = NSMutableAttributedString(string: "")
        var ranges: [NSRange] = []
        if let title = configuration.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            let titleStyle = NSMutableParagraphStyle()
            titleStyle.paragraphSpacing = CGFloat(configuration.paragraphSpacing + configuration.titleSpacing)
            titleStyle.alignment = .natural
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: configuration.fontFamily.uiFont(ofSize: CGFloat(configuration.fontSize + 8), weight: .bold),
                .foregroundColor: configuration.textColor,
                .paragraphStyle: titleStyle
            ]
            output.append(NSAttributedString(string: title + "\n", attributes: titleAttributes))
        }

        if let subtitle = configuration.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !subtitle.isEmpty {
            let subtitleStyle = NSMutableParagraphStyle()
            subtitleStyle.paragraphSpacing = CGFloat(configuration.titleSpacing)
            subtitleStyle.alignment = .natural
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: configuration.fontFamily.uiFont(ofSize: max(CGFloat(configuration.fontSize - 5), 12), weight: .regular),
                .foregroundColor: configuration.textColor.withAlphaComponent(0.62),
                .paragraphStyle: subtitleStyle
            ]
            output.append(NSAttributedString(string: subtitle + "\n", attributes: subtitleAttributes))
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(configuration.lineSpacing)
        paragraphStyle.paragraphSpacing = CGFloat(configuration.paragraphSpacing)
        // Indent only the first line. Applying the same value to `headIndent`
        // indents every wrapped line and makes long paragraphs look clipped.
        paragraphStyle.headIndent = 0
        paragraphStyle.firstLineHeadIndent = CGFloat(configuration.paragraphIndent)
        paragraphStyle.alignment = .natural
        let paragraphAttributes: [NSAttributedString.Key: Any] = [
            .font: configuration.fontFamily.uiFont(ofSize: CGFloat(configuration.fontSize), weight: .regular),
            .foregroundColor: configuration.textColor,
            .kern: configuration.letterSpacing,
            .paragraphStyle: paragraphStyle
        ]
        // Build the chapter body as one plain string and apply one shared
        // attribute run. Appending an attributed string for every paragraph
        // creates thousands of temporary objects and fragmented layout runs
        // for long novels; the ranges remain paragraph-addressable for speech
        // highlighting and visibility tracking.
        let bodyStart = output.length
        var body = String()
        var bodyLength = 0
        for paragraph in configuration.paragraphs {
            let start = bodyStart + bodyLength
            ranges.append(NSRange(location: start, length: paragraph.utf16.count))
            body.append(paragraph)
            body.append("\n")
            bodyLength += paragraph.utf16.count + 1
        }
        if !body.isEmpty {
            output.append(NSAttributedString(string: body))
            output.addAttributes(
                paragraphAttributes,
                range: NSRange(location: bodyStart, length: bodyLength)
            )

            // Special styling for continuous chapter dividers
            for (idx, paragraph) in configuration.paragraphs.enumerated() {
                if paragraph.hasPrefix("——— ") && paragraph.hasSuffix(" ———") {
                    let range = ranges[idx]
                    let dividerStyle = NSMutableParagraphStyle()
                    dividerStyle.alignment = .center
                    dividerStyle.paragraphSpacingBefore = CGFloat(configuration.paragraphSpacing + 36)
                    dividerStyle.paragraphSpacing = CGFloat(configuration.paragraphSpacing + 18)
                    let dividerAttrs: [NSAttributedString.Key: Any] = [
                        .font: configuration.fontFamily.uiFont(ofSize: CGFloat(configuration.fontSize + 4), weight: .bold),
                        .foregroundColor: configuration.textColor,
                        .paragraphStyle: dividerStyle
                    ]
                    output.addAttributes(dividerAttrs, range: range)
                }
            }

            replacingImageParagraphs(
                output: output,
                ranges: &ranges,
                paragraphs: configuration.paragraphs,
                baseOffset: 0,
                configuration: configuration
            )
        }

        if configuration.showChapterEndBadge, !configuration.paragraphs.isEmpty {
            let endMarkerStyle = NSMutableParagraphStyle()
            endMarkerStyle.alignment = .center
            endMarkerStyle.paragraphSpacingBefore = CGFloat(configuration.paragraphSpacing + 24)
            endMarkerStyle.paragraphSpacing = CGFloat(configuration.paragraphSpacing + 8)
            let endAttributes: [NSAttributedString.Key: Any] = [
                .font: configuration.fontFamily.uiFont(ofSize: 13, weight: .regular),
                .foregroundColor: configuration.textColor.withAlphaComponent(0.42),
                .paragraphStyle: endMarkerStyle
            ]
            output.append(NSAttributedString(string: "— — — 本章完 — — —\n", attributes: endAttributes))
        }

        PerformanceSignpost.event("reader.textLayout.summary", "paragraphs=\(ranges.count), utf16=\(bodyLength)")
        return Result(text: output, paragraphRanges: ranges)
    }

    static func makeAttributedChunk(
        paragraphs: [String],
        startingLocation: Int,
        configuration: NativeReaderTextView.Configuration
    ) -> Result {
        let output = NSMutableAttributedString(string: "")
        var ranges: [NSRange] = []

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(configuration.lineSpacing)
        paragraphStyle.paragraphSpacing = CGFloat(configuration.paragraphSpacing)
        paragraphStyle.headIndent = 0
        paragraphStyle.firstLineHeadIndent = CGFloat(configuration.paragraphIndent)
        paragraphStyle.alignment = .natural
        let paragraphAttributes: [NSAttributedString.Key: Any] = [
            .font: configuration.fontFamily.uiFont(ofSize: CGFloat(configuration.fontSize), weight: .regular),
            .foregroundColor: configuration.textColor,
            .kern: configuration.letterSpacing,
            .paragraphStyle: paragraphStyle
        ]

        var body = String()
        var bodyLength = 0
        for paragraph in paragraphs {
            let start = startingLocation + bodyLength
            ranges.append(NSRange(location: start, length: paragraph.utf16.count))
            body.append(paragraph)
            body.append("\n")
            bodyLength += paragraph.utf16.count + 1
        }

        if !body.isEmpty {
            output.append(NSAttributedString(string: body))
            output.addAttributes(
                paragraphAttributes,
                range: NSRange(location: 0, length: bodyLength)
            )

            // Divider styling for continuous chapter titles
            for (idx, paragraph) in paragraphs.enumerated() {
                if paragraph.hasPrefix("——— ") && paragraph.hasSuffix(" ———") {
                    let range = NSRange(location: ranges[idx].location - startingLocation, length: ranges[idx].length)
                    let dividerStyle = NSMutableParagraphStyle()
                    dividerStyle.alignment = .center
                    dividerStyle.paragraphSpacingBefore = CGFloat(configuration.paragraphSpacing + 36)
                    dividerStyle.paragraphSpacing = CGFloat(configuration.paragraphSpacing + 18)
                    let dividerAttrs: [NSAttributedString.Key: Any] = [
                        .font: configuration.fontFamily.uiFont(ofSize: CGFloat(configuration.fontSize + 4), weight: .bold),
                        .foregroundColor: configuration.textColor,
                        .paragraphStyle: dividerStyle
                    ]
                    output.addAttributes(dividerAttrs, range: range)
                }
            }

            replacingImageParagraphs(
                output: output,
                ranges: &ranges,
                paragraphs: paragraphs,
                baseOffset: startingLocation,
                configuration: configuration
            )
        }

        return Result(text: output, paragraphRanges: ranges)
    }

    private static func replacingImageParagraphs(
        output: NSMutableAttributedString,
        ranges: inout [NSRange],
        paragraphs: [String],
        baseOffset: Int,
        configuration: NativeReaderTextView.Configuration
    ) {
        for idx in (0..<paragraphs.count).reversed() {
            let paragraph = paragraphs[idx]
            guard let url = ReaderImageSizingPolicy.imageURL(in: paragraph) else { continue }
            let oldRange = ranges[idx]
            let attachmentAttrString = makeAttachment(for: url, configuration: configuration)
            let rangeInOutput = NSRange(location: oldRange.location - baseOffset, length: oldRange.length)
            output.replaceCharacters(in: rangeInOutput, with: attachmentAttrString)
            let newLength = attachmentAttrString.length
            let delta = newLength - oldRange.length
            ranges[idx] = NSRange(location: oldRange.location, length: newLength)
            for j in (idx + 1)..<ranges.count {
                ranges[j].location += delta
            }
        }
    }

    static func makeAttachment(
        for url: URL,
        configuration: NativeReaderTextView.Configuration
    ) -> NSAttributedString {
        let containerWidth: CGFloat = {
            if configuration.imageColumnWidth > 0 {
                return configuration.imageColumnWidth
            }
            return 320
        }()

        // Derive the height ceiling from the measured column instead of a
        // hard-coded 320pt so split view and landscape keep the same ratio.
        let maximumHeight: CGFloat? = configuration.imageStyle.stretchesToColumnWidth
            ? nil
            : max(containerWidth * 0.72, 220)

        let cached = RemoteImageLoader.shared.cachedImage(for: url)
        let targetSize: CGSize
        let image: UIImage
        if let cached {
            image = cached
            targetSize = ReaderImageSizingPolicy.size(
                for: cached.size,
                style: configuration.imageStyle,
                containerWidth: containerWidth,
                maximumHeight: maximumHeight
            )
        } else {
            let placeholderWidth = configuration.imageStyle.stretchesToColumnWidth
                ? containerWidth
                : min(containerWidth, 260)
            let placeholderHeight = configuration.imageStyle.stretchesToColumnWidth
                ? min(containerWidth * 0.6, 220)
                : min(max(placeholderWidth * 0.62, 120), 200)
            targetSize = CGSize(width: max(placeholderWidth, 1), height: max(placeholderHeight, 1))
            image = placeholderImage(size: targetSize, textColor: configuration.textColor)
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(origin: .zero, size: targetSize)

        let imgStyle = NSMutableParagraphStyle()
        imgStyle.alignment = .center
        imgStyle.paragraphSpacingBefore = CGFloat(configuration.paragraphSpacing + 8)
        imgStyle.paragraphSpacing = CGFloat(configuration.paragraphSpacing + 8)

        let attrString = NSMutableAttributedString(attachment: attachment)
        attrString.addAttributes([.paragraphStyle: imgStyle], range: NSRange(location: 0, length: attrString.length))
        return attrString
    }

    static func placeholderImage(size: CGSize, textColor: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
            textColor.withAlphaComponent(0.06).setFill()
            path.fill()

            let strokeColor = textColor.withAlphaComponent(0.12)
            strokeColor.setStroke()
            path.lineWidth = 1
            path.stroke()

            let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
            if let photoIcon = UIImage(systemName: "photo", withConfiguration: config)?.withTintColor(textColor.withAlphaComponent(0.35), renderingMode: .alwaysOriginal) {
                let iconSize = photoIcon.size
                let iconOrigin = CGPoint(
                    x: (size.width - iconSize.width) / 2,
                    y: (size.height - iconSize.height) / 2 - 8
                )
                photoIcon.draw(at: iconOrigin)
            }

            let text = "加载插图中..." as NSString
            let textFont = UIFont.systemFont(ofSize: 11, weight: .regular)
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: textFont,
                .foregroundColor: textColor.withAlphaComponent(0.4)
            ]
            let textSize = text.size(withAttributes: textAttrs)
            let textOrigin = CGPoint(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2 + 16
            )
            text.draw(at: textOrigin, withAttributes: textAttrs)
        }
    }
}

