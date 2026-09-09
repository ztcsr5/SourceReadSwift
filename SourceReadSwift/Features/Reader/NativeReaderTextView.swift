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
    let onVisibleParagraph: (Int) -> Void
    var onNearBottom: (() -> Void)? = nil
    var onReachTop: (() -> Void)? = nil
    var onReachBottom: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onVisibleParagraph: onVisibleParagraph,
            onReachTop: onReachTop,
            onReachBottom: onReachBottom,
            onNearBottom: onNearBottom
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
        textView.layoutManager.allowsNonContiguousLayout = true
        textView.decelerationRate = .normal
        textView.setContentHuggingPriority(.defaultLow, for: .vertical)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        context.coordinator.attach(textView)
        context.coordinator.update(textView: textView, configuration: configuration, scrollTarget: scrollTarget, scrollRequestKey: scrollRequestKey)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.updateCallbacks(
            visibleParagraph: onVisibleParagraph,
            reachTop: onReachTop,
            reachBottom: onReachBottom,
            nearBottom: onNearBottom
        )
        context.coordinator.update(textView: textView, configuration: configuration, scrollTarget: scrollTarget, scrollRequestKey: scrollRequestKey)
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
            showChapterEndBadge: showChapterEndBadge
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
            showChapterEndBadge: Bool = false
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
                showChapterEndBadge: showChapterEndBadge
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
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIScrollViewDelegate {
        private weak var textView: UITextView?
        private var visibleParagraphCallback: (Int) -> Void
        private var reachTopCallback: (() -> Void)?
        private var reachBottomCallback: (() -> Void)?
        private var nearBottomCallback: (() -> Void)?
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

        init(
            onVisibleParagraph: @escaping (Int) -> Void,
            onReachTop: (() -> Void)? = nil,
            onReachBottom: (() -> Void)? = nil,
            onNearBottom: (() -> Void)? = nil
        ) {
            visibleParagraphCallback = onVisibleParagraph
            reachTopCallback = onReachTop
            reachBottomCallback = onReachBottom
            nearBottomCallback = onNearBottom
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
            nearBottom: (() -> Void)?
        ) {
            visibleParagraphCallback = visibleParagraph
            reachTopCallback = reachTop
            reachBottomCallback = reachBottom
            nearBottomCallback = nearBottom
        }

        func updateSelection(_ enabled: Bool, in textView: UITextView) {
            guard lastSelectionEnabled != enabled else { return }
            lastSelectionEnabled = enabled
            textView.isSelectable = enabled
        }

        func update(textView: UITextView, configuration newConfiguration: Configuration, scrollTarget: Int?, scrollRequestKey: String?) {
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
                    if contentChanged && !isAppend {
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
            guard !isAppend else { return }
            guard let scrollTarget,
                  newConfiguration.paragraphs.indices.contains(scrollTarget),
                  scrollRequestKey != lastScrollRequestKey else { return }
            guard scrollToParagraph(scrollTarget, in: textView, animated: newConfiguration.animatedScrollDuration > 0, duration: newConfiguration.animatedScrollDuration) else { return }
            lastScrollRequestKey = scrollRequestKey
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

        private func rebuild(textView: UITextView, configuration: Configuration) {
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
        }

        private func updateInsets(in textView: UITextView, configuration: Configuration) {
            let insets = UIEdgeInsets(
                top: CGFloat(configuration.pagePadding),
                left: CGFloat(configuration.pagePadding),
                bottom: CGFloat(configuration.pagePadding + configuration.footerHeight),
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
        }

        private func setContentOffsetIfNeeded(_ offset: CGPoint, in textView: UITextView) {
            let current = textView.contentOffset
            guard abs(current.x - offset.x) > 0.5 || abs(current.y - offset.y) > 0.5 else { return }
            textView.setContentOffset(offset, animated: false)
        }

        @discardableResult
        private func scrollToParagraph(_ index: Int, in textView: UITextView, animated: Bool, duration: Double) -> Bool {
            guard paragraphRanges.indices.contains(index) else { return false }
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
            let targetY = ReaderScrollPositionPolicy.targetContentOffsetY(
                textRectMinY: rect.minY,
                textContainerInsetTop: textView.textContainerInset.top,
                boundsHeight: textView.bounds.height,
                contentSizeHeight: textView.contentSize.height,
                adjustedContentInset: textView.adjustedContentInset
            )
            let offset = CGPoint(x: 0, y: targetY)
            let currentOffset = textView.contentOffset
            hasAppliedInitialScrollTarget = true
            guard abs(currentOffset.y - offset.y) > 0.5 else { return true }
            if animated {
                UIView.animate(
                    withDuration: min(max(duration * 0.9, 0.25), 8),
                    delay: 0,
                    options: [.curveLinear, .beginFromCurrentState, .allowUserInteraction, .allowAnimatedContent]
                ) {
                    textView.setContentOffset(offset, animated: false)
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
            let visibleRect = CGRect(
                x: 0,
                y: max(textView.contentOffset.y - textView.textContainerInset.top, 0),
                width: textView.bounds.width,
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
        let desiredY = textRectMinY - textContainerInsetTop
        return min(max(desiredY, minimumY), maximumY)
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
            output.append(NSAttributedString(string: "——— 本章完 · 继续上拉进入下一章 ———\n", attributes: endAttributes))
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
        }

        return Result(text: output, paragraphRanges: ranges)
    }
}
