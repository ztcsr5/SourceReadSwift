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
    var fontFamily: ReaderFontFamily = .system
    let fontSize: Double
    let lineSpacing: Double
    let pagePadding: Double
    let letterSpacing: Double
    let paragraphSpacing: Double
    let paragraphIndent: Double
    let titleSpacing: Double
    let footerHeight: Double
    let textColor: UIColor
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
    var onReachBottom: (() -> Void)? = nil
    /// One tap-zone page step in continuous scroll mode. `generation` is
    /// monotonic so the same direction can be requested twice in a row
    /// without SwiftUI diffing the two requests as equal.
    var pageStepDirection: Int = 0
    var pageStepGeneration: Int = 0
    var onPageStepBoundary: ((Int) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onVisibleParagraph: onVisibleParagraph,
            onReachTop: onReachTop,
            onReachBottom: onReachBottom,
            onNearBottom: onNearBottom,
            onPageStepBoundary: onPageStepBoundary
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
            reachBottom: onReachBottom,
            nearBottom: onNearBottom,
            pageStepBoundary: onPageStepBoundary
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
            fontFamily: fontFamily,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            pagePadding: pagePadding,
            letterSpacing: letterSpacing,
            paragraphSpacing: paragraphSpacing,
            paragraphIndent: paragraphIndent,
            titleSpacing: titleSpacing,
            footerHeight: footerHeight,
            textColor: textColor,
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
        let fontFamily: ReaderFontFamily
        let fontSize: Double
        let lineSpacing: Double
        let pagePadding: Double
        let letterSpacing: Double
        let paragraphSpacing: Double
        let paragraphIndent: Double
        let titleSpacing: Double
        let footerHeight: Double
        let textColor: UIColor
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
            fontFamily: ReaderFontFamily = .system,
            fontSize: Double,
            lineSpacing: Double,
            pagePadding: Double,
            letterSpacing: Double,
            paragraphSpacing: Double,
            paragraphIndent: Double,
            titleSpacing: Double,
            footerHeight: Double,
            textColor: UIColor,
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
            self.fontFamily = fontFamily
            self.fontSize = fontSize
            self.lineSpacing = lineSpacing
            self.pagePadding = pagePadding
            self.letterSpacing = letterSpacing
            self.paragraphSpacing = paragraphSpacing
            self.paragraphIndent = paragraphIndent
            self.titleSpacing = titleSpacing
            self.footerHeight = footerHeight
            self.textColor = textColor
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
            InsetsSignature(pagePadding: pagePadding, footerHeight: footerHeight)
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
                && lhs.textColor.isEqual(rhs.textColor)
                && lhs.highlightColor.isEqual(rhs.highlightColor)
                && lhs.animatedScrollDuration == rhs.animatedScrollDuration
                && lhs.showChapterEndBadge == rhs.showChapterEndBadge
                && lhs.isAppendedUpdate == rhs.isAppendedUpdate
                && lhs.imageStyle == rhs.imageStyle
                && lhs.imageHeaders == rhs.imageHeaders
                && abs(lhs.imageColumnWidth - rhs.imageColumnWidth) < 0.5
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIScrollViewDelegate {
        private weak var textView: UITextView?
        private var visibleParagraphCallback: (Int) -> Void
        private var reachTopCallback: (() -> Void)?
        private var reachBottomCallback: (() -> Void)?
        private var nearBottomCallback: (() -> Void)?
        private var pageStepBoundaryCallback: ((Int) -> Void)?
        private var lastPageStepGeneration = 0
        private var configuration: Configuration?
        private var paragraphRanges: [NSRange] = []
        private var lastHighlightedParagraph = -1
        private var lastHighlightColor: UIColor?
        private var lastScrollRequestKey: String?
        private var lastVisibleParagraph = -1
        private var lastVisibleUpdateAt: CFTimeInterval = 0
        private var didConfigureTextView = false
        private var lastSelectionEnabled: Bool?
        private var lastLayoutWidth: CGFloat?
        private var hasAppliedInitialScrollTarget = false
        private var didFireNearBottom = false
        private var isProgrammaticScrolling = false
        private var illustrationLoadTask: Task<Void, Never>?
        private var illustrationGeneration = 0
        private static let illustrationLoadConcurrency = 4

        init(
            onVisibleParagraph: @escaping (Int) -> Void,
            onReachTop: (() -> Void)? = nil,
            onReachBottom: (() -> Void)? = nil,
            onNearBottom: (() -> Void)? = nil,
            onPageStepBoundary: ((Int) -> Void)? = nil
        ) {
            visibleParagraphCallback = onVisibleParagraph
            reachTopCallback = onReachTop
            reachBottomCallback = onReachBottom
            nearBottomCallback = onNearBottom
            pageStepBoundaryCallback = onPageStepBoundary
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
            reachBottom: (() -> Void)?,
            nearBottom: (() -> Void)?,
            pageStepBoundary: ((Int) -> Void)?
        ) {
            visibleParagraphCallback = visibleParagraph
            reachTopCallback = reachTop
            reachBottomCallback = reachBottom
            nearBottomCallback = nearBottom
            pageStepBoundaryCallback = pageStepBoundary
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
            let isAppend = newConfiguration.isAppendedUpdate
            let widthChanged: Bool = {
                guard textView.bounds.width > 1 else { return false }
                guard let lastLayoutWidth else { return true }
                return abs(lastLayoutWidth - textView.bounds.width) > 0.5
            }()
            configuration = newConfiguration

            if textLayoutChanged || widthChanged {
                let previousOffset = textView.contentOffset
                let canFastAppend = isAppend
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
                    rebuild(textView: textView, configuration: newConfiguration)
                    if textView.bounds.width > 1 {
                        lastLayoutWidth = textView.bounds.width
                    }
                    if textView.bounds.height > 0 && (!contentChanged || isAppend) {
                        setContentOffsetIfNeeded(previousOffset, in: textView)
                    }
                    // A new chapter needs its initial target; settings/theme
                    // changes or appends preserve the existing offset and request key.
                    let isDifferentChapter = previousConfiguration?.title != newConfiguration.title
                    if isDifferentChapter && !isAppend {
                        lastScrollRequestKey = nil
                        hasAppliedInitialScrollTarget = (scrollTarget == nil || scrollTarget == 0)
                    }
                    if isAppend {
                        didFireNearBottom = false
                    }
                    lastVisibleParagraph = -1
                    lastVisibleUpdateAt = 0
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

        private func updateInsets(in textView: UITextView, configuration: Configuration) {
            // The representable already lives inside the top safe area. Adding
            // `safeTop` again produced a double inset (a large blank strip above
            // the first line) and disagreed with the paged surface, which starts
            // from the same safe-area origin.
            let topInset = ReaderPageLayoutEngine.minimumTopInset(pagePadding: CGFloat(configuration.pagePadding))
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
            textView.textContainerInset = insets
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

        private func restoreScrollAnchor(_ anchor: ReaderScrollAnchorPolicy.Anchor?, in textView: UITextView) {
            guard let anchor,
                  let characterIndex = ReaderScrollAnchorPolicy.characterIndex(for: anchor, in: paragraphRanges),
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
            isProgrammaticScrolling = true
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction, .allowAnimatedContent]
            ) {
                textView.setContentOffset(CGPoint(x: 0, y: targetY), animated: false)
            } completion: { [weak self, weak textView] _ in
                self?.isProgrammaticScrolling = false
                if let textView {
                    self?.updateVisibleParagraph(in: textView)
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
            guard abs(currentOffset.y - offset.y) > 0.5 else { return true }
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
            return true
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
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
                    nearBottomCallback?()
                }
            } else if visibleBottom < contentHeight - 900 {
                didFireNearBottom = false
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
            }
        }
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

    static func characterIndex(for anchor: Anchor, in paragraphRanges: [NSRange]) -> Int? {
        guard paragraphRanges.indices.contains(anchor.paragraphIndex) else { return nil }
        let range = paragraphRanges[anchor.paragraphIndex]
        guard range.length > 0 else { return nil }
        return range.location + min(max(anchor.characterOffset, 0), range.length - 1)
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

