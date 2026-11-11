import SwiftUI
import UIKit
import WebKit
import QuartzCore
#if DEBUG
import OSLog
#endif

/// Gives an edge swipe to UIKit before the prose scroll pan can claim it.
/// Which WebKit-internal recognizers must lose to the system edge return.
/// Only drag-like recognizers are gated: requiring the edge gesture to fail
/// before a tap would delay or swallow ordinary in-prose taps.
enum ReaderEdgeReturnGesturePolicy {
    static func shouldWaitForSystemEdge(_ gesture: UIGestureRecognizer) -> Bool {
        gesture is UIPanGestureRecognizer || gesture is UILongPressGestureRecognizer
    }
}
final class ReaderEdgeReturnWebView: WKWebView {
    /// How far the failure dependency reaches. Production gates the whole
    /// WebKit subtree; the isolated experiment walks back through the earlier
    /// scopes so all of them stay measurable in one launch.
    enum EdgeGateScope {
        /// Only `scrollView.panGestureRecognizer` (the pre-fix production path).
        case scrollViewPanOnly
        /// Every recognizer attached directly to `WKScrollView`.
        case scrollViewRecognizers
        /// Every drag recognizer below `WKScrollView`, including
        /// `WKContentView`'s highlight long-press and WebKit's inner pan.
        case webKitSubtree
    }
    static var edgeGateScope: EdgeGateScope = .webKitSubtree
    private(set) weak var prioritizedEdgeReturn: UIGestureRecognizer?
    #if DEBUG
    private var isObservingScrollPan = false
    private var scrollPanBeganCount = 0
    private var scrollPanChangedCount = 0
    private var lastScrollPanTranslation = CGPoint.zero
    private var lastScrollPanState = UIGestureRecognizer.State.possible

    var scrollPanEvidence: String {
        let pan = scrollView.panGestureRecognizer
        return "webPan=\(ObjectIdentifier(pan)),enabled=\(pan.isEnabled),state=\(pan.state.rawValue),"
            + "began=\(scrollPanBeganCount),changed=\(scrollPanChangedCount),"
            + "lastState=\(lastScrollPanState.rawValue),dx=\(lastScrollPanTranslation.x),dy=\(lastScrollPanTranslation.y),"
            + "priority=\(prioritizedEdgeReturn.map { String(describing: ObjectIdentifier($0)) } ?? "none")"
    }

    @objc private func recordScrollPan(_ pan: UIPanGestureRecognizer) {
        // Observe the existing pan without changing its delegate or failure dependencies.
        // This counter must remain separate from native-return movement evidence.
        lastScrollPanTranslation = pan.translation(in: scrollView)
        lastScrollPanState = pan.state
        if pan.state == .began { scrollPanBeganCount += 1 }
        if pan.state == .changed { scrollPanChangedCount += 1 }
    }
    #endif

    override func didMoveToWindow() {
        super.didMoveToWindow()
        #if DEBUG
        if window != nil, !isObservingScrollPan {
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(recordScrollPan(_:)))
            isObservingScrollPan = true
        } else if window == nil, isObservingScrollPan {
            scrollView.panGestureRecognizer.removeTarget(self, action: #selector(recordScrollPan(_:)))
            isObservingScrollPan = false
        }
        #endif
        installEdgeReturnPriority()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        installEdgeReturnPriority()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A hosting/navigation ancestor may acquire its recognizer after the
        // web view enters the window. Retry at layout, not just on that move.
        installEdgeReturnPriority()
    }

    private func installEdgeReturnPriority() {
        guard #available(iOS 18.0, *), window != nil else { return }
        var responder: UIResponder? = next
        while let current = responder {
            if let host = current as? UIViewController,
               let navigation = host.navigationController ?? (host as? UINavigationController),
               let edgeReturn = navigation.interactivePopGestureRecognizer,
               let gestureHost = edgeReturn.view, isDescendant(of: gestureHost) {
                // WebKit can install new recognizers later (highlight,
                // selection, find-in-page). Re-running is cheap:
                // `require(toFail:)` on an already gated pair is a no-op.
                prioritizedEdgeReturn = edgeReturn
                // This public recognizer handles only the leading edge. Do
                // not depend on iOS 26's full-content pop or replace delegates.
                switch Self.edgeGateScope {
                case .webKitSubtree:
                    gateEveryDragRecognizer(below: edgeReturn)
                case .scrollViewRecognizers:
                    for gesture in scrollView.gestureRecognizers ?? [] where gesture !== edgeReturn {
                        guard ReaderEdgeReturnGesturePolicy.shouldWaitForSystemEdge(gesture) else { continue }
                        gesture.require(toFail: edgeReturn)
                    }
                case .scrollViewPanOnly:
                    // Pre-fix behaviour, retained so every earlier scope stays
                    // measurable in one launch.
                    scrollView.panGestureRecognizer.require(toFail: edgeReturn)
                }
                return
            }
            responder = current.next
        }
    }

    /// Gates drag recognizers across the WebKit subtree, not only the ones
    /// attached to `WKScrollView` itself.
    ///
    /// Third-round evidence (80 controlled rounds): 17/17 ignored edge drags had
    /// `WKHighlightLongPressGestureRecognizer` begin; 63/63 working drags had it
    /// stay quiet. Neither that recognizer (hosted by `WKContentView`) nor
    /// WebKit's inner `UIPanGestureRecognizer` appears in
    /// `scrollView.gestureRecognizers`, so the previous loop could never gate
    /// them.
    private func gateEveryDragRecognizer(below edgeReturn: UIGestureRecognizer) {
        for gesture in Self.dragRecognizers(in: scrollView) where gesture !== edgeReturn {
            // Tap recognizers stay out: requiring the system edge gesture to
            // fail would delay or swallow ordinary in-prose taps.
            guard ReaderEdgeReturnGesturePolicy.shouldWaitForSystemEdge(gesture) else { continue }
            gesture.require(toFail: edgeReturn)
        }
    }

    /// Depth- and count-bounded walk so installing priority can repeat from
    /// `layoutSubviews` without walking an unbounded tree on every frame.
    static func dragRecognizers(in root: UIView, depthLimit: Int = 4,
                               nodeLimit: Int = 64) -> [UIGestureRecognizer] {
        var pending: [(view: UIView, depth: Int)] = [(root, 0)]
        var recognizers: [UIGestureRecognizer] = []
        var visited = 0
        while let entry = pending.popLast() {
            visited += 1
            guard visited <= nodeLimit else { break }
            recognizers.append(contentsOf: entry.view.gestureRecognizers ?? [])
            guard entry.depth < depthLimit else { continue }
            pending.append(contentsOf: entry.view.subviews.map { (view: $0, depth: entry.depth + 1) })
        }
        return recognizers
    }
}

/// Continuous reading surface rendered by `WKWebView`.
///
/// The TextKit surface rebuilt one giant attributed string for the whole
/// chapter window on every window mutation, and every rebuild ran on the main
/// thread between two scroll frames. That is the source of the three symptoms
/// the reader kept reporting: a jump to a chapter blanked the screen because
/// the text storage was emptied before the new layout was ready, fast swipes
/// dropped frames because a rebuild landed inside a drag, and chapter titles
/// looked like body text because a flat paragraph array has no title identity.
///
/// The WebView surface keeps the same public contract as `NativeReaderTextView`
/// but owns the text as DOM nodes:
///
/// * content updates patch the existing document instead of reloading it, so a
///   chapter handoff never unmounts the visible text;
/// * the document itself anchors a chapter insertion by paragraph identity, so
///   prepending a chapter does not move the line under the eye;
/// * titles are real `h1`/`h2` elements with their own CSS rule;
/// * a tap becomes a zone event only when it is short, still and unambiguous,
///   which keeps scrolling from being mistaken for a page turn.
struct WebScrollReaderView: UIViewRepresentable {
    @Environment(\.nativeReaderSession) private var nativeSession
    let sections: [WebReaderSection]
    var contentFingerprint: String
    /// 换书 / 重进阅读器时的身份串。变了就把文档滚回顶部。
    var resetToken: String = ""
    var fontFamily: ReaderFontFamily = .system
    let fontSize: Double
    var chapterTitleSize: Double = 0
    var chapterTitleBold: Bool = true
    var chapterTitleFamily: ReaderFontFamily? = nil
    var chapterDecoration: ReaderChapterDecoration = .none
    var chapterAlignment: ReaderChapterAlignment = .leading
    let lineSpacing: Double
    let pagePadding: Double
    let letterSpacing: Double
    let paragraphSpacing: Double
    let paragraphIndent: Double
    let titleSpacing: Double
    let footerHeight: Double
    /// 顶部留白由阅读器按当前 chrome 状态给出；WebView 用 CSS 内边距实现，
    /// 不用 UIScrollView 的 contentInset，避免主题切换时正文整体位移。
    var topInset: Double? = nil
    let textColor: UIColor
    var surfaceColor: UIColor = .clear
    let highlightColor: UIColor
    let currentParagraphIndex: Int
    let scrollTarget: Int?
    let scrollRequestKey: String?
    var isOpeningPositionPrepared = true
    var scrollTargetUTF16Offset: Int = 0
    let animatedScrollDuration: Double
    let textSelectionEnabled: Bool
    var showChapterEndBadge: Bool = false
    var traditionalChineseEnabled: Bool = false
    var bionicReadingEnabled: Bool = false
    var imageStyle: ReaderImageStyle = .standard
    var imageHeaders: [String: String] = [:]
    var imageColumnWidth: CGFloat = 0
    var prioritizesSystemEdgeReturn = false
    let onVisibleParagraph: (Int) -> Void
    var onVisiblePosition: ((Int, Int) -> Void)? = nil
    var onPresented: (() -> Void)? = nil
    var onScrollInteractionChanged: ((Bool) -> Void)? = nil
    var onNearBottom: (() -> Void)? = nil
    var onReachTop: (() -> Void)? = nil
    var onNearTop: (() -> Void)? = nil
    var onReachBottom: (() -> Void)? = nil
    var pageStepDirection: Int = 0
    var pageStepGeneration: Int = 0
    var onPageStepBoundary: ((Int) -> Void)? = nil
    var onScrollTargetApplied: (() -> Void)? = nil
    /// Short tap reported by the document, in CSS pixels (== points inside a
    /// `width=device-width` viewport). The reader turns it into a tap-zone
    /// action so scroll mode keeps the same 3x3 configuration as the paged
    /// modes.
    var onTap: ((CGPoint) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(view: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        context.coordinator.makeWebView(initialView: self)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(view: self, webView: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.tearDown(webView: webView)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, UIScrollViewDelegate {
        private var view: WebScrollReaderView
        private weak var webView: WKWebView?
        private let imageHandler = ReaderImageSchemeHandler()
        private let fontHandler = ReaderFontSchemeHandler()
        #if DEBUG
        private static let startupEvents = Logger(subsystem: "com.edc21.SourceReadSwift.book-passage", category: "startup")
        private static let recordsStartupEvidence =
            ProcessInfo.processInfo.arguments.contains("--floating-desk-regression")
            || ProcessInfo.processInfo.arguments.contains("--reader-settings-regression")
        #endif

        private var isDocumentReady = false
        private var navigationToken: String?
        private var shellNavigation: WKNavigation?
        private var startupProbeTask: Task<Void, Never>?
        private var hasReportedPosition = false
        private var hasPresented = false
        private var presentationRequestKey: String?
        private(set) var startupRecoveryCount = 0
        private var lastStylePayload: WebReaderStylePayload?
        private var lastStyleInputs: [AnyHashable]?
        private(set) var styleBuildCount = 0
        private var lastContentFingerprint: String?
        private var mountedContent: WebReaderContentPayloadBuilder.Snapshot?
        private var firstMountedChapter: Int?
        private var reportingSections: [WebReaderSection] = []
        private var reportingResetToken: String?
        private var expectedContentRevision = ""
        private var contentBuildTask: Task<Void, Never>?
        private var isBuildingContent = false
        private var buildingRevision = ""
        private var hasDeferredContent = false
        private var deferredContentTask: Task<Void, Never>?
        private(set) var isScrollInteractionActive = false
        private var lastDeferredScrollUpdate: CFTimeInterval = 0
        private(set) var contentMountCount = 0
        private var lastHighlight = Int.min
        private var lastPageStepGeneration: Int
        private var lastResetToken: String?
        private var lastSentScrollKey: String?
        private var inlineOpeningScrollRevision: String?
        private var appliedScrollKey: String?
        private var pendingScrollKey: String?
        private var pendingScrollTarget: Int?
        private var pendingScrollUTF16Offset = 0
        /// Retry budget is per scroll request: a second book must not inherit
        /// the exhausted budget of the previous one.
        private var openingScrollRetryKey: String?
        private var openingScrollRetryCount = 0
        private var lastSurfaceColor: UIColor?
        /// 文档级脚本错误的自愈次数上限：连坏两次说明是内容或样式的问题，
        /// 再重建只会循环，交给上层占位/错误态。
        private var recoveredDocumentFailures = 0

        init(view: WebScrollReaderView) {
            self.view = view
            self.lastPageStepGeneration = view.pageStepGeneration
            super.init()
        }

        func makeWebView(initialView: WebScrollReaderView, prepareBeforeNavigation: ((WKWebView) -> Void)? = nil) -> WKWebView {
            view = initialView
            let configuration = WKWebViewConfiguration()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            configuration.suppressesIncrementalRendering = true
            // 数据检测（电话/地址自动变链接）在 iOS 上是 configuration 的属性，
            // 关掉才不会被提取出来的正文里的号码触发链接改写。
            configuration.dataDetectorTypes = []
            configuration.setURLSchemeHandler(imageHandler, forURLScheme: WebReaderImageScheme.name)
            configuration.setURLSchemeHandler(fontHandler, forURLScheme: ReaderFontResource.scheme)
            configuration.userContentController.add(self, name: "reader")
            #if DEBUG
            if ReaderEdgeInputTrace.isRequested { ReaderEdgeInputTrace.install(in: configuration.userContentController) }
            #endif

            let webView: WKWebView = view.prioritizesSystemEdgeReturn
                ? ReaderEdgeReturnWebView(frame: .zero, configuration: configuration)
                : WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            webView.uiDelegate = self
            webView.isOpaque = false
            webView.backgroundColor = view.surfaceColor
            webView.scrollView.backgroundColor = view.surfaceColor
            webView.scrollView.contentInsetAdjustmentBehavior = .never
            webView.scrollView.showsVerticalScrollIndicator = false
            webView.scrollView.showsHorizontalScrollIndicator = false
            webView.scrollView.decelerationRate = .normal
            webView.scrollView.bounces = true
            webView.scrollView.alwaysBounceVertical = true
            webView.scrollView.scrollsToTop = true
            webView.allowsLinkPreview = false
            webView.scrollView.delaysContentTouches = false
            webView.scrollView.canCancelContentTouches = true
            webView.accessibilityIdentifier = "reader.webScrollSurface"
            webView.scrollView.delegate = self
            self.webView = webView
            lastSurfaceColor = view.surfaceColor
            view.nativeSession?.recordWebView(webView)

            prepareBeforeNavigation?(webView)
            navigateToShell(webView: webView)
            return webView
        }

        func tearDown(webView: WKWebView) {
            deferredContentTask?.cancel()
            deferredContentTask = nil
            hasDeferredContent = false
            webView.scrollView.delegate = nil
            startupProbeTask?.cancel()
            startupProbeTask = nil
            contentBuildTask?.cancel()
            buildingRevision = UUID().uuidString
            navigationToken = nil
            shellNavigation = nil
            expectedContentRevision = UUID().uuidString
            webView.stopLoading()
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "reader")
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            imageHandler.cancelAll()
            fontHandler.cancelAll()
        }

        func update(view newView: WebScrollReaderView, webView: WKWebView) {
            view = newView
            view.nativeSession?.recordBridgeEvent("update:\(newView.scrollTarget.map(String.init) ?? "nil")")
            self.webView = webView
            imageHandler.headers = newView.imageHeaders

            if !newView.surfaceColor.isEqual(lastSurfaceColor) {
                lastSurfaceColor = newView.surfaceColor
                webView.backgroundColor = newView.surfaceColor
                webView.scrollView.backgroundColor = newView.surfaceColor
            }

            guard isDocumentReady, view.isOpeningPositionPrepared else { return }

            pushStyleIfNeeded(webView: webView)

            let fingerprint = effectiveContentFingerprint(for: newView)
            if lastContentFingerprint != fingerprint {
                // A completed download must not lay out several offscreen chapters
                // in the middle of a native fling. Keep only the latest window.
                if isBuildingContent || shouldDeferContent(in: webView) {
                    hasDeferredContent = true
                    return
                }
                hasDeferredContent = false
                lastContentFingerprint = fingerprint
                pushContent(webView: webView)
            }

            guard !isBuildingContent else { return }

            pushResetIfNeeded(webView: webView)
            pushScrollTargetIfNeeded(webView: webView)
            pushPageStepIfNeeded(webView: webView)
            pushHighlightIfNeeded(webView: webView)
        }

        // MARK: JavaScript bridge

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            deferredContentTask?.cancel()
            isScrollInteractionActive = true
            view.onScrollInteractionChanged?(true)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard hasDeferredContent, !isBuildingContent, let webView,
                  !shouldDeferContent(in: webView) else { return }
            // Near the end of the window every scroll frame used to rebuild the
            // content fingerprint and walk the push* checks while WebKit was
            // also appending a chapter. 100 ms still gives the three-screen
            // runway plenty of time; the interaction-end path forces a final
            // update so a completed download is never stranded.
            let now = CACurrentMediaTime()
            guard now - lastDeferredScrollUpdate >= 0.1 else { return }
            lastDeferredScrollUpdate = now
            update(view: view, webView: webView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { finishScrollInteraction() }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            finishScrollInteraction()
        }

        private func finishScrollInteraction() {
            isScrollInteractionActive = false
            view.onScrollInteractionChanged?(false)
            deferredContentTask?.cancel()
            // Give a deferred window trim one update to join the same patch.
            deferredContentTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 80_000_000) }
                catch { return }
                guard let self, !self.isScrollInteractionActive, let webView = self.webView else { return }
                self.update(view: self.view, webView: webView)
            }
        }

        private func shouldDeferContent(in webView: WKWebView) -> Bool {
            guard hasReportedPosition, lastResetToken == view.resetToken,
                  view.scrollTarget == nil || view.scrollRequestKey == appliedScrollKey else { return false }
            let scroll = webView.scrollView
            guard isScrollInteractionActive || scroll.isTracking || scroll.isDragging || scroll.isDecelerating else { return false }
            // Backward loading at the top is user-visible work as well.
            if let first = view.sections.first?.chapterIndex, let mounted = firstMountedChapter,
               first < mounted, scroll.contentOffset.y < scroll.bounds.height { return false }
            // Keep three screens of runway even during a long fling.
            let remaining = scroll.contentSize.height - scroll.contentOffset.y - scroll.bounds.height
            return remaining > max(scroll.bounds.height * 3, 1)
        }

        private func effectiveContentFingerprint(for currentView: WebScrollReaderView) -> String {
            "\(currentView.resetToken)|\(currentView.contentFingerprint)|tc=\(currentView.traditionalChineseEnabled ? 1 : 0)|end=\(currentView.showChapterEndBadge ? 1 : 0)"
        }

        private func pushStyleIfNeeded(webView: WKWebView) {
            let accent = AppTheme.accentUIColor
            var inputs: [AnyHashable] = [view.fontFamily.rawValue, view.fontSize, view.lineSpacing,
                view.pagePadding, view.letterSpacing, view.paragraphSpacing, view.paragraphIndent,
                view.titleSpacing, view.footerHeight, view.topInset ?? -1]
            inputs += [WebReaderColor.hex(view.textColor), WebReaderColor.hex(view.surfaceColor),
                WebReaderColor.hex(view.highlightColor), WebReaderColor.hex(accent),
                view.textSelectionEnabled, view.bionicReadingEnabled, view.chapterTitleSize, view.chapterTitleBold]
            inputs += [view.chapterTitleFamily?.rawValue ?? "", view.chapterDecoration.rawValue, view.chapterAlignment.rawValue,
                UserDefaults.standard.string(forKey: "reader.customFontPostScriptName") ?? "", CustomFontLocations.revision]
            guard inputs != lastStyleInputs else { return }
            lastStyleInputs = inputs
            styleBuildCount += 1
            var payload = WebReaderStylePayload.make(
                fontFamily: view.fontFamily,
                fontSize: view.fontSize,
                lineSpacing: view.lineSpacing,
                pagePadding: view.pagePadding,
                letterSpacing: view.letterSpacing,
                paragraphSpacing: view.paragraphSpacing,
                paragraphIndent: view.paragraphIndent,
                titleSpacing: view.titleSpacing,
                footerHeight: view.footerHeight,
                topInset: view.topInset,
                textColor: view.textColor,
                surfaceColor: view.surfaceColor,
                highlightColor: view.highlightColor,
                accentColor: accent,
                selectable: view.textSelectionEnabled,
                bionicReadingEnabled: view.bionicReadingEnabled
            )
            payload.applyChapterHeading(size: view.chapterTitleSize, family: view.chapterTitleFamily,
                                        isBold: view.chapterTitleBold, bodyFamily: view.fontFamily)
            payload.chapterArt = view.chapterDecoration.cssImage(ink: view.textColor)
            payload.chapterAlignment = view.chapterAlignment.css
            // Custom font CSS may be several MB. Never stringify the whole JSON
            // merely to decide whether an unchanged scroll update needs a bridge call.
            guard payload != lastStylePayload else { return }
            lastStylePayload = payload
            call(function: "setStyle", jsonObject: payload.jsonObject, webView: webView)
        }

        private func pushContent(webView: WKWebView, canReuseMountedSections: Bool = true) {
            view.nativeSession?.recordOpeningStage("building")
            contentBuildTask?.cancel()
            let revision = UUID().uuidString
            buildingRevision = revision
            isBuildingContent = true
            let sections = view.sections
            let fingerprint = effectiveContentFingerprint(for: view)
            let snapshot = WebReaderContentPayloadBuilder.Snapshot(
                sections: sections, showChapterEndBadge: view.showChapterEndBadge,
                traditionalChineseEnabled: view.traditionalChineseEnabled, revision: revision
            )
            let base = canReuseMountedSections ? mountedContent : nil
            contentBuildTask = Task { @MainActor [weak self, weak webView] in
                let literal = await Task.detached(priority: .userInitiated) {
                    WebReaderContentPayloadBuilder.json(sections: sections, snapshot: snapshot, reusing: base)
                        .map(WebReaderJavaScriptLiteral.string)
                }.value
                guard !Task.isCancelled, let self, let webView,
                      self.buildingRevision == revision, self.isDocumentReady else { return }
                guard let literal else {
                    self.isBuildingContent = false
                    NSLog("Reader could not serialize a chapter window")
                    return
                }
                // A drag may have started while JSON was being built. Keep the
                // mounted revision valid so visible-position reports still work.
                while self.shouldDeferContent(in: webView) {
                    do { try await Task.sleep(nanoseconds: 50_000_000) }
                    catch { return }
                    guard !Task.isCancelled, self.buildingRevision == revision, self.isDocumentReady else { return }
                }
                if self.hasDeferredContent && self.effectiveContentFingerprint(for: self.view) != fingerprint {
                    self.isBuildingContent = false
                    self.update(view: self.view, webView: webView)
                    return
                }
                self.hasDeferredContent = false
                self.expectedContentRevision = revision
                self.view.nativeSession?.recordOpeningStage("mounting")
                self.reportingSections = sections
                self.reportingResetToken = self.view.resetToken
                // A newer update racing an in-flight call must use a full window,
                // not assume either revision is the one mounted in WebKit.
                self.mountedContent = nil
                let resetToken = self.view.resetToken
                let reportsOpeningPosition = !self.hasReportedPosition && self.view.scrollTarget == nil
                let resetsOpeningPosition = reportsOpeningPosition && self.lastResetToken != resetToken
                let mount = "window.__reader.setContent(JSON.parse(\(literal)), \(resetsOpeningPosition), \(reportsOpeningPosition))"
                let openingJump = self.prepareInlineOpeningScroll(revision: revision)
                // A cold compositor can defer a second native-to-WebKit call
                // behind the cover. Mount and position in one JS evaluation;
                // the normal revision, cursor and render acknowledgements still apply.
                let script = openingJump.map { "(function() { if (!\(mount)) return false; \($0) return true; })()" }
                    ?? mount
                webView.evaluateJavaScript(script) {
                    [weak self, weak webView] value, error in
                    guard let self, let webView, self.expectedContentRevision == revision,
                          self.isDocumentReady else { return }
                    guard error == nil, (value as? Bool) == true else {
                        self.discardFailedInlineOpeningScroll(revision: revision)
                        if base != nil {
                            self.pushContent(webView: webView, canReuseMountedSections: false)
                        } else {
                            self.isBuildingContent = false
                            NSLog("Reader did not mount a full chapter window, bridge code=%ld", (error as NSError?)?.code ?? 0)
                        }
                        return
                    }
                    self.mountedContent = snapshot
                    if openingJump == nil || self.pendingScrollKey != nil {
                        self.view.nativeSession?.recordOpeningStage("mounted")
                    }
                    self.firstMountedChapter = sections.first?.chapterIndex
                    self.contentMountCount += 1
                    self.isBuildingContent = false
                    if resetsOpeningPosition, self.view.resetToken == resetToken, self.view.scrollTarget == nil {
                        self.lastResetToken = resetToken
                    }
                    self.update(view: self.view, webView: webView)
                    // A pure prefetch append updates the revision without another position report.
                    // Rebind the pending render acknowledgement to that successfully mounted revision.
                    self.schedulePresentationAcknowledgement()
                }
            }
        }

        private func pushResetIfNeeded(webView: WKWebView) {
            guard !isBuildingContent else { return }
            let token = view.resetToken
            guard lastResetToken != token else { return }
            lastResetToken = token
            // 有明确跳转目标时由目标决定落点；没有目标才回顶部，
            // 否则「换书复用同一个 WKWebView」会把上一本的滚动位置带过来。
            guard view.scrollTarget == nil else { return }
            view.nativeSession?.recordBridgeEvent("reset")
            webView.evaluateJavaScript("window.__reader.resetScroll();", completionHandler: nil)
        }

        private func pushScrollTargetIfNeeded(webView: WKWebView) {
            guard !isBuildingContent else { return }
            guard prepareScrollTarget() else { return }
            evaluateScrollTarget(webView: webView)
        }

        private func prepareScrollTarget() -> Bool {
            guard let target = view.scrollTarget, let key = view.scrollRequestKey,
                  key != lastSentScrollKey else { return false }
            lastSentScrollKey = key
            pendingScrollKey = key
            pendingScrollTarget = target
            pendingScrollUTF16Offset = max(view.scrollTargetUTF16Offset, 0)
            return true
        }

        private func prepareInlineOpeningScroll(revision: String) -> String? {
            guard !hasReportedPosition, pendingScrollKey == nil,
                  view.animatedScrollDuration <= 0.05, prepareScrollTarget() else { return nil }
            inlineOpeningScrollRevision = revision
            lastResetToken = view.resetToken
            return scrollTargetScript()
        }

        private func discardFailedInlineOpeningScroll(revision: String) {
            guard inlineOpeningScrollRevision == revision else { return }
            inlineOpeningScrollRevision = nil
            guard pendingScrollKey != nil else { return }
            lastSentScrollKey = nil
            lastResetToken = nil
            pendingScrollKey = nil
            pendingScrollTarget = nil
        }

        private func scrollTargetScript() -> String? {
            guard let target = pendingScrollTarget, let key = pendingScrollKey else { return nil }
            view.nativeSession?.recordBridgeEvent("jump:\(target)")
            let animated = view.animatedScrollDuration > 0.05
            let verifiesOpeningPosition = !hasReportedPosition
            return "window.__reader.scrollToFlat(\(target), \(animated ? "true" : "false"), \(WebReaderJavaScriptLiteral.string(key)), \(WebReaderJavaScriptLiteral.string(expectedContentRevision)), \(pendingScrollUTF16Offset), \(verifiesOpeningPosition));"
        }

        private func evaluateScrollTarget(webView: WKWebView) {
            guard let script = scrollTargetScript() else { return }
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        private func pushPageStepIfNeeded(webView: WKWebView) {
            guard !isBuildingContent else { return }
            guard view.pageStepGeneration != lastPageStepGeneration else { return }
            lastPageStepGeneration = view.pageStepGeneration
            guard view.pageStepDirection != 0 else { return }
            let direction = view.pageStepDirection > 0 ? 1 : -1
            let script = "window.__reader.pageStep(\(direction));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        private func pushHighlightIfNeeded(webView: WKWebView) {
            guard !isBuildingContent else { return }
            guard view.currentParagraphIndex != lastHighlight else { return }
            lastHighlight = view.currentParagraphIndex
            let script = "window.__reader.highlight(\(view.currentParagraphIndex));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        private func call(function: String, jsonObject: [String: Any], webView: WKWebView) {
            guard JSONSerialization.isValidJSONObject(jsonObject),
                  let data = try? JSONSerialization.data(withJSONObject: jsonObject, options: []),
                  let text = String(data: data, encoding: .utf8) else { return }
            let literal = WebReaderJavaScriptLiteral.string(text)
            let script = "window.__reader.\(function)(JSON.parse(\(literal)));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        // MARK: WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "reader",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            // Bootstrap messages predate the first chapter revision. Use the
            // shell identity so an aborted load cannot activate or reload its successor.
            if type == "ready" || type == "fatal" {
                guard let navigationToken, body["navigationToken"] as? String == navigationToken else { return }
            } else {
                guard ReaderWebMessagePolicy.matchesRevision(body["revision"] as? String, expected: expectedContentRevision) else { return }
            }

            #if DEBUG
            if type == "edge-input" {
                guard ReaderEdgeInputTrace.isRequested, message.frameInfo.isMainFrame,
                      let phase = body["phase"] as? String, ["began", "ended", "cancelled"].contains(phase),
                      let sequence = body["sequence"] as? Int, sequence > 0,
                      let displacement = body["dx"] as? Int, (-4096...4096).contains(displacement) else { return }
                view.nativeSession?.recordBridgeEvent("edge-\(phase):\(sequence):dx=\(displacement)")
                return
            }
            #endif
            switch type {
            case "ready":
                // didFinish or a bounded probe may already have activated it.
                // A late acknowledgement cannot discard a valid mounted revision.
                if let webView { activateDocumentIfNeeded(webView: webView) }
            case "content-ready":
                if inlineOpeningScrollRevision != expectedContentRevision,
                   pendingScrollKey != nil, pendingScrollKey != appliedScrollKey, let webView {
                    evaluateScrollTarget(webView: webView)
                }
            case "visible":
                let start = CACurrentMediaTime()
                defer { ReaderScrollPerfMeter.record(cost: CACurrentMediaTime() - start) }
                guard reportingResetToken == view.resetToken, pendingScrollKey == nil,
                      view.scrollTarget == nil || view.scrollRequestKey == appliedScrollKey,
                      let reportedFlat = body["flat"] as? Int,
                      let flat = ReaderWebPositionMapper.remap(reportedFlat, from: reportingSections, to: view.sections) else { return }
                if flat >= 0 {
                    if !hasReportedPosition {
                        hasReportedPosition = true
                        startupProbeTask?.cancel()
                        startupProbeTask = nil
                        #if DEBUG
                        if Self.recordsStartupEvidence {
                            let requested = view.scrollTarget == nil ? 0 : 1
                            let applied = appliedScrollKey == nil ? 0 : 1
                            Self.startupEvents.notice("BOOT_VISIBLE requested=\(requested, privacy: .public) applied=\(applied, privacy: .public)")
                        }
                        #endif
                    }
                    let offset = (body["utf16Offset"] as? Int) ?? 0
                    view.onVisiblePosition?(flat, max(offset, 0))
                    view.onVisibleParagraph(flat)
                    schedulePresentationAcknowledgement()
                }
            case "presented":
                guard !hasPresented, pendingScrollKey == nil,
                      reportingResetToken == view.resetToken,
                      view.scrollTarget == nil || view.scrollRequestKey == appliedScrollKey,
                      body["requestKey"] as? String == (appliedScrollKey ?? "") else { return }
                hasPresented = true
                #if DEBUG
                if ReaderEdgeInputTrace.isRequested {
                    let installed = body["edgeTraceInstalled"] as? Bool == true
                    view.nativeSession?.recordBridgeEvent(installed ? "edge-trace:ready" : "edge-trace:missing")
                }
                #endif
                view.nativeSession?.recordOpeningStage("presented")
                view.nativeSession?.recordPresentedContent()
                view.onPresented?()
            case "near-bottom":
                guard reportingResetToken == view.resetToken, pendingScrollKey == nil else { return }
                let start = CACurrentMediaTime()
                defer { ReaderScrollPerfMeter.record(cost: CACurrentMediaTime() - start) }
                view.onNearBottom?()
            case "near-top":
                guard reportingResetToken == view.resetToken, pendingScrollKey == nil else { return }
                let start = CACurrentMediaTime()
                defer { ReaderScrollPerfMeter.record(cost: CACurrentMediaTime() - start) }
                view.onNearTop?()
            case "reach-bottom":
                guard reportingResetToken == view.resetToken, pendingScrollKey == nil else { return }
                let start = CACurrentMediaTime()
                defer { ReaderScrollPerfMeter.record(cost: CACurrentMediaTime() - start) }
                view.onReachBottom?()
            case "reach-top":
                guard reportingResetToken == view.resetToken, pendingScrollKey == nil else { return }
                let start = CACurrentMediaTime()
                defer { ReaderScrollPerfMeter.record(cost: CACurrentMediaTime() - start) }
                view.onReachTop?()
            case "page-boundary":
                guard let direction = body["direction"] as? Int else { return }
                view.onPageStepBoundary?(direction > 0 ? 1 : -1)
            case "tap":
                view.nativeSession?.recordContentTap()
                guard !view.textSelectionEnabled else { return }
                guard let x = body["x"] as? Double, let y = body["y"] as? Double else { return }
                view.onTap?(CGPoint(x: x, y: y))
            case "scroll-applied":
                guard ReaderWebMessagePolicy.matchesRequest(body["requestKey"] as? String, pending: pendingScrollKey) else { return }
                view.nativeSession?.recordBridgeEvent("applied:\(pendingScrollTarget.map(String.init) ?? "nil")")
                appliedScrollKey = pendingScrollKey
                view.nativeSession?.recordOpeningStage("positioned")
                pendingScrollKey = nil
                pendingScrollTarget = nil
                view.onScrollTargetApplied?()
            case "scroll-miss":
                // `scroll-miss` now means the document kept the paragraph out
                // of the viewport across a full bounded frame sequence, not
                // that the node was briefly missing. Two silent outcomes hid
                // real failures: an opening that never moved (scrollY stayed 0
                // with the saved paragraph 3069 pt below) still reached
                // `scroll-applied`, and a true miss posted nothing back. Retry
                // a bounded number of times, then keep the reader covered
                // instead of presenting an unpositioned page.
                guard let retryKey = pendingScrollKey, let webView else { return }
                if openingScrollRetryKey != retryKey {
                    openingScrollRetryKey = retryKey
                    openingScrollRetryCount = 0
                }
                guard openingScrollRetryCount < 2 else { return }
                openingScrollRetryCount += 1
                view.nativeSession?.recordBridgeEvent("retry:\(pendingScrollTarget.map(String.init) ?? "nil")")
                lastSentScrollKey = nil
                pendingScrollKey = nil
                pendingScrollTarget = nil
                pushScrollTargetIfNeeded(webView: webView)
            case "fatal":
                // 文档脚本抛错后 WebKit 会停在空白半渲染状态，滚动手势也没反应。
                // 重建一次文档（保留当前内容与目标段落），比让用户退 App 强。
                if let webView, recoveredDocumentFailures < 2 {
                    recoveredDocumentFailures += 1
                    isDocumentReady = false
                    contentBuildTask?.cancel()
                    mountedContent = nil
                    expectedContentRevision = UUID().uuidString
                    lastContentFingerprint = nil
                    lastStylePayload = nil
                    lastStyleInputs = nil
                    lastSentScrollKey = nil
                    pendingScrollKey = nil
                    pendingScrollTarget = nil
                    navigateToShell(webView: webView)
                }
            default:
                break
            }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // The surface is a document, not a browser: an <a> inside extracted
            // content must never replace the reading text.
            guard navigationAction.navigationType == .other || navigationAction.request.url?.scheme == "about" else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let shellNavigation, navigation === shellNavigation else { return }
            verifyStartupBridge(webView: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            NSLog("Reader WebKit content process terminated before position=%d", hasReportedPosition ? 0 : 1)
            if !hasReportedPosition { recoverStartupShell(webView: webView) }
        }

        private func activateDocumentIfNeeded(webView: WKWebView) {
            guard !isDocumentReady else { return }
            isDocumentReady = true
            guard view.isOpeningPositionPrepared else { return }
            pushStyleIfNeeded(webView: webView)
            lastContentFingerprint = effectiveContentFingerprint(for: view)
            pushContent(webView: webView)
            pushResetIfNeeded(webView: webView)
            pushScrollTargetIfNeeded(webView: webView)
            pushPageStepIfNeeded(webView: webView)
            pushHighlightIfNeeded(webView: webView)
        }

        private func navigateToShell(webView: WKWebView) {
            view.nativeSession?.recordShellLoad()
            hasPresented = false
            presentationRequestKey = nil
            let navigationID = UUID()
            navigationToken = navigationID.uuidString
            shellNavigation = webView.loadHTMLString(WebReaderHTML.renderShell(for: navigationID), baseURL: nil)
            if !hasReportedPosition { scheduleStartupProbe(webView: webView) }
        }

        private func schedulePresentationAcknowledgement() {
            guard !hasPresented, hasReportedPosition, pendingScrollKey == nil,
                  reportingResetToken == view.resetToken,
                  view.scrollTarget == nil || view.scrollRequestKey == appliedScrollKey,
                  let webView else { return }
            let key = expectedContentRevision + "|" + (appliedScrollKey ?? "")
            guard presentationRequestKey != key else { return }
            presentationRequestKey = key
            let revision = WebReaderJavaScriptLiteral.string(expectedContentRevision)
            let request = WebReaderJavaScriptLiteral.string(appliedScrollKey ?? "")
            #if DEBUG
            let traceField = ReaderEdgeInputTrace.isRequested
                ? ", edgeTraceInstalled: window.__sourceReadEdgeTraceInstalled === true" : ""
            #else
            let traceField = ""
            #endif
            // Position reporting stays synchronous. Revealing the reader additionally waits for render opportunities.
            let script = """
                window.requestAnimationFrame(function() {
                  window.requestAnimationFrame(function() {
                    window.webkit.messageHandlers.reader.postMessage({type:"presented", revision:\(revision), requestKey:\(request)\(traceField)});
                  });
                });
                """
            webView.evaluateJavaScript(script) { [weak self] _, error in
                guard let self, error != nil, self.presentationRequestKey == key else { return }
                self.presentationRequestKey = nil
                NavigationTrace.shared.mark("reader-session", "presentation acknowledgement unavailable")
            }
        }

        private func scheduleStartupProbe(webView: WKWebView) {
            startupProbeTask?.cancel()
            // Only startup checks at 2/5/7 seconds; a valid position cancels
            // all of them. This is not a sampler during normal reading.
            startupProbeTask = Task { @MainActor [weak self, weak webView] in
                for delay: UInt64 in [2_000_000_000, 3_000_000_000, 2_000_000_000] {
                    try? await Task.sleep(nanoseconds: delay)
                    guard !Task.isCancelled, let self, let webView, !self.hasReportedPosition,
                          webView.navigationDelegate === self else { return }
                    self.verifyStartupBridge(webView: webView)
                }
            }
        }

        private func verifyStartupBridge(webView: WKWebView) {
            guard !hasReportedPosition else { return }
            guard let navigationToken else { return }
            let navigationLiteral = WebReaderJavaScriptLiteral.string(navigationToken)
            #if DEBUG
            recordStartupEvidence(webView: webView)
            #endif
            let script = """
                (function() {
                  var bridge = window.__reader;
                  if (bridge && bridge.navigationToken === \(navigationLiteral) && typeof bridge.setContent === 'function') {
                    return 1;
                  }
                  return document.readyState === 'complete' ? -1 : 0;
                })()
                """
            webView.evaluateJavaScript(script) { [weak self, weak webView] value, error in
                guard let self, let webView, webView.navigationDelegate === self,
                      self.navigationToken == navigationToken, !self.hasReportedPosition else { return }
                if let error {
                    NSLog("Reader startup bridge probe failed, code=%ld", (error as NSError).code)
                    return
                }
                if (value as? Int) == 1 { self.activateDocumentIfNeeded(webView: webView) }
                // A completed empty document needs the same bounded recovery
                // as a broken shell. Do not cancel a navigation still loading.
                else if (value as? Int) == -1, !webView.isLoading { self.recoverStartupShell(webView: webView) }
            }
        }

        #if DEBUG
        private func recordStartupEvidence(webView: WKWebView) {
            guard Self.recordsStartupEvidence else { return }
            let script = """
                (function(){ return {ready:document.readyState,
                  bridge:!!(window.__reader && typeof window.__reader.setContent === 'function'),
                  shell:!!document.getElementById('content'), paragraphs:document.querySelectorAll('p').length}; })()
                """
            webView.evaluateJavaScript(script) { [weak self, weak webView] value, error in
                guard let self, let webView, !self.hasReportedPosition else { return }
                if let error {
                    let code = (error as NSError).code
                    Self.startupEvents.notice("BOOT_CHECK_ERROR code=\(code, privacy: .public)")
                    return
                }
                guard let snapshot = value as? [String: Any], let ready = snapshot["ready"] as? String,
                      ["loading", "interactive", "complete"].contains(ready) else { return }
                let bridge = (snapshot["bridge"] as? Bool) == true ? 1 : 0
                let shell = (snapshot["shell"] as? Bool) == true ? 1 : 0
                let paragraphs = snapshot["paragraphs"] as? Int ?? -1
                let loading = webView.isLoading ? 1 : 0
                let document = self.isDocumentReady ? 1 : 0
                let building = self.isBuildingContent ? 1 : 0
                let pending = self.pendingScrollKey != nil ? 1 : 0
                let applied = self.appliedScrollKey != nil ? 1 : 0
                webView.accessibilityValue = "ready=\(ready) bridge=\(bridge) shell=\(shell) paragraphs=\(paragraphs) loading=\(loading) document=\(document) building=\(building) pending=\(pending) applied=\(applied)"
                Self.startupEvents.notice("BOOT ready=\(ready, privacy: .public) bridge=\(bridge, privacy: .public) shell=\(shell, privacy: .public) paragraphs=\(paragraphs, privacy: .public) loading=\(loading, privacy: .public) document=\(document, privacy: .public) building=\(building, privacy: .public) pending=\(pending, privacy: .public) applied=\(applied, privacy: .public)")
            }
        }
        #endif

        private func recoverStartupShell(webView: WKWebView) {
            guard !hasReportedPosition, startupRecoveryCount == 0, recoveredDocumentFailures < 2 else { return }
            startupRecoveryCount += 1
            recoveredDocumentFailures += 1
            NSLog("Reader completed shell has no bridge; bounded startup recovery")
            isDocumentReady = false
            contentBuildTask?.cancel()
            isBuildingContent = false
            mountedContent = nil
            expectedContentRevision = UUID().uuidString
            lastContentFingerprint = nil
            lastStylePayload = nil
            lastStyleInputs = nil
            lastResetToken = nil
            lastSentScrollKey = nil
            appliedScrollKey = nil
            pendingScrollKey = nil
            pendingScrollTarget = nil
            lastHighlight = Int.min
            // The input cursor stays unchanged, and no visible position has
            // been published yet. Never apply this recovery to active reading.
            navigateToShell(webView: webView)
        }
    }
}

/// Serves chapter illustrations over `readerimg://` so the request can carry
/// the source's `Referer` / `User-Agent` (most Chinese image CDNs reject a bare
/// request) while staying inside the WebView's own document.
final class ReaderImageSchemeHandler: NSObject, WKURLSchemeHandler {
    var headers: [String: String] = [:]

    private let lock = NSLock()
    private var running: [ObjectIdentifier: Task<Void, Never>] = [:]

    private static let failure = NSError(
        domain: "SourceReadSwift.ReaderImage",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "image unavailable"]
    )

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              let original = WebReaderImageScheme.originalURL(from: requestURL.absoluteString) else {
            urlSchemeTask.didFailWithError(Self.failure)
            return
        }
        let headers = self.headers
        let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
        let task = Task { [weak self] in
            let image = await RemoteImageLoader.shared.image(for: original, headers: headers)
            let encoded = Self.encode(image: image)
            // WebKit expects the scheme task callbacks on the main thread.
            await MainActor.run {
                self?.finish(
                    identifier: identifier,
                    task: urlSchemeTask,
                    data: encoded?.data,
                    mimeType: encoded?.mimeType ?? "image/jpeg",
                    requestURL: requestURL
                )
            }
        }
        lock.lock()
        running[identifier] = task
        lock.unlock()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
        lock.lock()
        let task = running.removeValue(forKey: identifier)
        lock.unlock()
        task?.cancel()
    }

    func cancelAll() {
        lock.lock()
        let tasks = Array(running.values)
        running.removeAll()
        lock.unlock()
        for task in tasks { task.cancel() }
    }

    private static func encode(image: UIImage?) -> (data: Data, mimeType: String)? {
        guard let image else { return nil }
        if hasAlphaChannel(image), let pngData = image.pngData() {
            return (pngData, "image/png")
        }
        if let jpegData = image.jpegData(compressionQuality: 0.90) {
            return (jpegData, "image/jpeg")
        }
        if let pngData = image.pngData() {
            return (pngData, "image/png")
        }
        return nil
    }

    private static func hasAlphaChannel(_ image: UIImage) -> Bool {
        guard let alpha = image.cgImage?.alphaInfo else { return false }
        switch alpha {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        @unknown default:
            return false
        }
    }

    private func finish(identifier: ObjectIdentifier, task: WKURLSchemeTask, data: Data?, mimeType: String, requestURL: URL) {
        lock.lock()
        let stillRunning = running.removeValue(forKey: identifier) != nil
        lock.unlock()
        guard stillRunning else { return }

        guard let data else {
            task.didFailWithError(Self.failure)
            return
        }
        let response = URLResponse(
            url: requestURL,
            mimeType: mimeType,
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }
}
