import SwiftUI
import UIKit
import WebKit

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
    let sections: [WebReaderSection]
    var contentFingerprint: String
    /// 换书 / 重进阅读器时的身份串。变了就把文档滚回顶部。
    var resetToken: String = ""
    var fontFamily: ReaderFontFamily = .system
    let fontSize: Double
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
    let animatedScrollDuration: Double
    let textSelectionEnabled: Bool
    var showChapterEndBadge: Bool = false
    var traditionalChineseEnabled: Bool = false
    var bionicReadingEnabled: Bool = false
    var imageStyle: ReaderImageStyle = .standard
    var imageHeaders: [String: String] = [:]
    var imageColumnWidth: CGFloat = 0
    let onVisibleParagraph: (Int) -> Void
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

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        private var view: WebScrollReaderView
        private weak var webView: WKWebView?
        private let imageHandler = ReaderImageSchemeHandler()

        private var isDocumentReady = false
        private var lastStyleSignature: String?
        private var lastContentFingerprint: String?
        private var expectedContentRevision = ""
        private var contentBuildTask: Task<Void, Never>?
        private var isBuildingContent = false
        private var lastHighlight = Int.min
        private var lastPageStepGeneration: Int
        private var lastResetToken: String?
        private var lastSentScrollKey: String?
        private var appliedScrollKey: String?
        private var pendingScrollKey: String?
        private var pendingScrollTarget: Int?
        private var lastSurfaceColor: UIColor?
        /// 文档级脚本错误的自愈次数上限：连坏两次说明是内容或样式的问题，
        /// 再重建只会循环，交给上层占位/错误态。
        private var recoveredDocumentFailures = 0

        init(view: WebScrollReaderView) {
            self.view = view
            self.lastPageStepGeneration = view.pageStepGeneration
            super.init()
        }

        func makeWebView(initialView: WebScrollReaderView) -> WKWebView {
            view = initialView
            let configuration = WKWebViewConfiguration()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            configuration.suppressesIncrementalRendering = true
            // 数据检测（电话/地址自动变链接）在 iOS 上是 configuration 的属性，
            // 关掉才不会被提取出来的正文里的号码触发链接改写。
            configuration.dataDetectorTypes = []
            configuration.setURLSchemeHandler(imageHandler, forURLScheme: WebReaderImageScheme.name)
            configuration.userContentController.add(self, name: "reader")

            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            webView.uiDelegate = self
            webView.isOpaque = false
            webView.backgroundColor = view.surfaceColor
            webView.scrollView.backgroundColor = view.surfaceColor
            webView.scrollView.contentInsetAdjustmentBehavior = .never
            webView.scrollView.showsVerticalScrollIndicator = false
            webView.scrollView.showsHorizontalScrollIndicator = false
            webView.scrollView.bounces = true
            webView.scrollView.alwaysBounceVertical = true
            webView.scrollView.scrollsToTop = true
            webView.allowsLinkPreview = false
            webView.scrollView.delaysContentTouches = false
            webView.scrollView.canCancelContentTouches = true
            webView.accessibilityIdentifier = "reader.webScrollSurface"
            self.webView = webView
            lastSurfaceColor = view.surfaceColor

            webView.loadHTMLString(WebReaderHTML.shell, baseURL: nil)
            return webView
        }

        func tearDown(webView: WKWebView) {
            contentBuildTask?.cancel()
            expectedContentRevision = UUID().uuidString
            webView.stopLoading()
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "reader")
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            imageHandler.cancelAll()
        }

        func update(view newView: WebScrollReaderView, webView: WKWebView) {
            view = newView
            self.webView = webView
            imageHandler.headers = newView.imageHeaders

            if !newView.surfaceColor.isEqual(lastSurfaceColor) {
                lastSurfaceColor = newView.surfaceColor
                webView.backgroundColor = newView.surfaceColor
                webView.scrollView.backgroundColor = newView.surfaceColor
            }

            guard isDocumentReady else { return }

            pushStyleIfNeeded(webView: webView)

            let fingerprint = effectiveContentFingerprint(for: newView)
            if lastContentFingerprint != fingerprint {
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

        private func effectiveContentFingerprint(for currentView: WebScrollReaderView) -> String {
            "\(currentView.contentFingerprint)|tc=\(currentView.traditionalChineseEnabled ? 1 : 0)|end=\(currentView.showChapterEndBadge ? 1 : 0)"
        }

        private func pushStyleIfNeeded(webView: WKWebView) {
            let payload = WebReaderStylePayload.make(
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
                accentColor: AppTheme.accentUIColor,
                selectable: view.textSelectionEnabled,
                bionicReadingEnabled: view.bionicReadingEnabled
            )
            let signature = Self.signature(for: payload.jsonObject)
            guard signature != lastStyleSignature else { return }
            lastStyleSignature = signature
            call(function: "setStyle", jsonObject: payload.jsonObject, webView: webView)
        }

        private func pushContent(webView: WKWebView) {
            contentBuildTask?.cancel()
            let revision = UUID().uuidString
            expectedContentRevision = revision
            isBuildingContent = true
            let sections = view.sections
            let badge = view.showChapterEndBadge
            let traditional = view.traditionalChineseEnabled
            contentBuildTask = Task { @MainActor [weak self, weak webView] in
                let literal = await Task.detached(priority: .userInitiated) {
                    WebReaderContentPayloadBuilder.json(sections: sections, showChapterEndBadge: badge,
                        traditionalChineseEnabled: traditional, revision: revision).map(WebReaderJavaScriptLiteral.string)
                }.value
                guard !Task.isCancelled, let self, let webView,
                      self.expectedContentRevision == revision, self.isDocumentReady else { return }
                self.isBuildingContent = false
                guard let literal else { return }
                webView.evaluateJavaScript("window.__reader.setContent(JSON.parse(\(literal)));", completionHandler: nil)
                self.pushResetIfNeeded(webView: webView)
                self.pushScrollTargetIfNeeded(webView: webView)
                self.pushPageStepIfNeeded(webView: webView)
                self.pushHighlightIfNeeded(webView: webView)
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
            webView.evaluateJavaScript("window.__reader.resetScroll();", completionHandler: nil)
        }

        private func pushScrollTargetIfNeeded(webView: WKWebView) {
            guard !isBuildingContent else { return }
            guard let target = view.scrollTarget, let key = view.scrollRequestKey else { return }
            guard key != lastSentScrollKey else { return }
            lastSentScrollKey = key
            pendingScrollKey = key
            pendingScrollTarget = target
            evaluateScrollTarget(webView: webView)
        }

        private func evaluateScrollTarget(webView: WKWebView) {
            guard let target = pendingScrollTarget, let key = pendingScrollKey else { return }
            let animated = view.animatedScrollDuration > 0.05
            let script = "window.__reader.scrollToFlat(\(target), \(animated ? "true" : "false"), \(WebReaderJavaScriptLiteral.string(key)), \(WebReaderJavaScriptLiteral.string(expectedContentRevision)));"
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

        private static func signature(for object: [String: Any]) -> String {
            let keys = object.keys.sorted()
            return keys.map { key in
                let value = object[key] ?? ""
                return "\(key)=\(value)"
            }.joined(separator: "|")
        }

        // MARK: WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "reader",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            // A flat index only has meaning in the DOM version that produced
            // it. Old WebKit messages must never be mapped through a new window.
            if type != "ready" && type != "fatal" {
                guard ReaderWebMessagePolicy.matchesRevision(body["revision"] as? String, expected: expectedContentRevision) else { return }
            }

            switch type {
            case "ready":
                isDocumentReady = true
                if let webView {
                    pushStyleIfNeeded(webView: webView)
                    lastContentFingerprint = effectiveContentFingerprint(for: view)
                    pushContent(webView: webView)
                    pushResetIfNeeded(webView: webView)
                    pushScrollTargetIfNeeded(webView: webView)
                    pushPageStepIfNeeded(webView: webView)
                    pushHighlightIfNeeded(webView: webView)
                }
            case "content-ready":
                if pendingScrollKey != nil, pendingScrollKey != appliedScrollKey, let webView {
                    evaluateScrollTarget(webView: webView)
                }
            case "visible":
                let start = CACurrentMediaTime()
                defer { ReaderScrollPerfMeter.record(cost: CACurrentMediaTime() - start) }
                guard pendingScrollKey == nil,
                      view.scrollTarget == nil || view.scrollRequestKey == appliedScrollKey,
                      let flat = body["flat"] as? Int else { return }
                if flat >= 0 { view.onVisibleParagraph(flat) }
            case "near-bottom":
                guard pendingScrollKey == nil else { return }
                let start = CACurrentMediaTime()
                defer { ReaderScrollPerfMeter.record(cost: CACurrentMediaTime() - start) }
                view.onNearBottom?()
            case "near-top":
                guard pendingScrollKey == nil else { return }
                let start = CACurrentMediaTime()
                defer { ReaderScrollPerfMeter.record(cost: CACurrentMediaTime() - start) }
                view.onNearTop?()
            case "reach-bottom":
                guard pendingScrollKey == nil else { return }
                let start = CACurrentMediaTime()
                defer { ReaderScrollPerfMeter.record(cost: CACurrentMediaTime() - start) }
                view.onReachBottom?()
            case "reach-top":
                guard pendingScrollKey == nil else { return }
                let start = CACurrentMediaTime()
                defer { ReaderScrollPerfMeter.record(cost: CACurrentMediaTime() - start) }
                view.onReachTop?()
            case "page-boundary":
                guard let direction = body["direction"] as? Int else { return }
                view.onPageStepBoundary?(direction > 0 ? 1 : -1)
            case "tap":
                guard !view.textSelectionEnabled else { return }
                guard let x = body["x"] as? Double, let y = body["y"] as? Double else { return }
                view.onTap?(CGPoint(x: x, y: y))
            case "scroll-applied":
                guard ReaderWebMessagePolicy.matchesRequest(body["requestKey"] as? String, pending: pendingScrollKey) else { return }
                appliedScrollKey = pendingScrollKey
                pendingScrollKey = nil
                pendingScrollTarget = nil
                view.onScrollTargetApplied?()
            case "scroll-miss":
                // The requested paragraph is not in the document yet; the next
                // content update retries through `content-ready`.
                break
            case "fatal":
                // 文档脚本抛错后 WebKit 会停在空白半渲染状态，滚动手势也没反应。
                // 重建一次文档（保留当前内容与目标段落），比让用户退 App 强。
                if let webView, recoveredDocumentFailures < 2 {
                    recoveredDocumentFailures += 1
                    isDocumentReady = false
                    contentBuildTask?.cancel()
                    expectedContentRevision = UUID().uuidString
                    lastContentFingerprint = nil
                    lastStyleSignature = nil
                    lastSentScrollKey = nil
                    pendingScrollKey = nil
                    pendingScrollTarget = nil
                    webView.loadHTMLString(WebReaderHTML.shell, baseURL: nil)
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
            // The document itself reports readiness through the message bridge;
            // this only covers a reload where the script failed to run.
            if !isDocumentReady {
                isDocumentReady = true
                pushStyleIfNeeded(webView: webView)
                lastContentFingerprint = effectiveContentFingerprint(for: view)
                pushContent(webView: webView)
                pushResetIfNeeded(webView: webView)
                pushScrollTargetIfNeeded(webView: webView)
            }
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
