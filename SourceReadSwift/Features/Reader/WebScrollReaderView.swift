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
        private var lastHighlight = Int.min
        private var lastPageStepGeneration: Int
        private var lastSentScrollKey: String?
        private var appliedScrollKey: String?
        private var pendingScrollKey: String?
        private var pendingScrollTarget: Int?
        private var lastSurfaceColor: UIColor?

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
            webView.backgroundColor = .clear
            webView.scrollView.backgroundColor = .clear
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

            if lastContentFingerprint != newView.contentFingerprint {
                lastContentFingerprint = newView.contentFingerprint
                pushContent(webView: webView)
            }

            pushScrollTargetIfNeeded(webView: webView)
            pushPageStepIfNeeded(webView: webView)
            pushHighlightIfNeeded(webView: webView)
        }

        // MARK: JavaScript bridge

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
                selectable: view.textSelectionEnabled
            )
            let signature = Self.signature(for: payload.jsonObject)
            guard signature != lastStyleSignature else { return }
            lastStyleSignature = signature
            call(function: "setStyle", jsonObject: payload.jsonObject, webView: webView)
        }

        private func pushContent(webView: WKWebView) {
            let payload = WebReaderContentPayloadBuilder.payload(
                sections: view.sections,
                showChapterEndBadge: view.showChapterEndBadge
            )
            call(function: "setContent", jsonObject: payload, webView: webView)
        }

        private func pushScrollTargetIfNeeded(webView: WKWebView) {
            guard let target = view.scrollTarget, let key = view.scrollRequestKey else { return }
            guard key != lastSentScrollKey else { return }
            lastSentScrollKey = key
            pendingScrollKey = key
            pendingScrollTarget = target
            evaluateScrollTarget(webView: webView)
        }

        private func evaluateScrollTarget(webView: WKWebView) {
            guard let target = pendingScrollTarget else { return }
            let animated = view.animatedScrollDuration > 0.05
            let script = "window.__reader.scrollToFlat(\(target), \(animated ? "true" : "false"));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        private func pushPageStepIfNeeded(webView: WKWebView) {
            guard view.pageStepGeneration != lastPageStepGeneration else { return }
            lastPageStepGeneration = view.pageStepGeneration
            guard view.pageStepDirection != 0 else { return }
            let direction = view.pageStepDirection > 0 ? 1 : -1
            let script = "window.__reader.pageStep(\(direction));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        private func pushHighlightIfNeeded(webView: WKWebView) {
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

            switch type {
            case "ready":
                isDocumentReady = true
                if let webView {
                    pushStyleIfNeeded(webView: webView)
                    lastContentFingerprint = view.contentFingerprint
                    pushContent(webView: webView)
                    pushScrollTargetIfNeeded(webView: webView)
                    pushPageStepIfNeeded(webView: webView)
                    pushHighlightIfNeeded(webView: webView)
                }
            case "content-ready":
                if pendingScrollKey != nil, pendingScrollKey != appliedScrollKey, let webView {
                    evaluateScrollTarget(webView: webView)
                }
            case "visible":
                guard let flat = body["flat"] as? Int else { return }
                if flat >= 0 { view.onVisibleParagraph(flat) }
            case "near-bottom":
                view.onNearBottom?()
            case "near-top":
                view.onNearTop?()
            case "reach-bottom":
                view.onReachBottom?()
            case "reach-top":
                view.onReachTop?()
            case "page-boundary":
                guard let direction = body["direction"] as? Int else { return }
                view.onPageStepBoundary?(direction > 0 ? 1 : -1)
            case "tap":
                guard let x = body["x"] as? Double, let y = body["y"] as? Double else { return }
                view.onTap?(CGPoint(x: x, y: y))
            case "scroll-applied":
                appliedScrollKey = pendingScrollKey
                pendingScrollKey = nil
                pendingScrollTarget = nil
                view.onScrollTargetApplied?()
            case "scroll-miss":
                // The requested paragraph is not in the document yet; the next
                // content update retries through `content-ready`.
                break
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
                lastContentFingerprint = view.contentFingerprint
                pushContent(webView: webView)
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
            let data = image?.jpegData(compressionQuality: 0.86)
            // WebKit expects the scheme task callbacks on the main thread.
            await MainActor.run {
                self?.finish(identifier: identifier, task: urlSchemeTask, data: data, requestURL: requestURL)
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

    private func finish(identifier: ObjectIdentifier, task: WKURLSchemeTask, data: Data?, requestURL: URL) {
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
            mimeType: "image/jpeg",
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }
}
