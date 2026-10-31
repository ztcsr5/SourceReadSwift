import SwiftUI
import WebKit

@MainActor
final class WebReadingSession: ObservableObject {
    weak var webView: WKWebView?
    @Published var article: SmartWebArticle?
    @Published var isExtracting = false
    @Published var errorMessage: String?
    private var extractionID = UUID()
    private(set) var documentGeneration: UInt64 = 0

    func documentDidStartLoading() {
        documentGeneration &+= 1
        cancelExtraction()
        article = nil
    }

    func cancelExtraction() {
        extractionID = UUID()
        isExtracting = false
    }

    func extractCurrentPage() {
        guard let webView, !isExtracting else { return }
        isExtracting = true
        errorMessage = nil
        let id = UUID()
        extractionID = id
        let pageURL = webView.url
        let document = documentGeneration
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self, weak webView] value, error in
            guard let self, let webView, self.extractionID == id, self.documentGeneration == document else { return }
            guard error == nil, let html = value as? String else {
                self.isExtracting = false
                self.errorMessage = error?.localizedDescription ?? "无法读取当前网页"
                return
            }
            Task { @MainActor [weak self, weak webView] in
                let result = await Task.detached(priority: .userInitiated) {
                    SmartWebArticleExtractor.extract(html: html, fallbackTitle: pageURL?.host ?? "网页文章")
                }.value
                guard let self, let webView, self.extractionID == id, self.documentGeneration == document else { return }
                self.isExtracting = false
                guard self.webView === webView, webView.url == pageURL else {
                    self.errorMessage = "页面已切换，请重新提取当前页"
                    return
                }
                if result.paragraphs.isEmpty { self.errorMessage = "未识别到正文，请打开文章或章节页后重试" }
                else { self.article = result }
            }
        }
    }
}

enum WebAdvertisementRules {
    // Deliberately narrow: no blanket script blocking, login/paywall removal,
    // or broad [class*=ad] selectors that can hide legitimate reading content.
    static let json: String = {
        // WebKit content blockers accept only a restricted regex dialect.
        // ICU matching alone is not a compilation test; avoid alternation.
        var rules: [[String: Any]] = ["doubleclick.net", "googlesyndication.com", "adservice.google.com"].map { domain in
            let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
            return ["trigger": ["url-filter": "^https?://([^/]+\\.)?\(escaped)/"], "action": ["type": "block"]]
        }
        rules.append(["trigger": ["url-filter": ".*"], "action": ["type": "css-display-none", "selector": "ins.adsbygoogle,[id^=google_ads_],iframe[src*=doubleclick]"]])
        return String(data: try! JSONSerialization.data(withJSONObject: rules), encoding: .utf8)!
    }()

    @MainActor
    static func compile(enabled: Bool, completion: @escaping (WKContentRuleList?, Error?) -> Void) {
        guard enabled else { completion(nil, nil); return }
        let store = WKContentRuleListStore.default()!
        let identifier = "inpage-conservative-ads-v2"
        store.lookUpContentRuleList(forIdentifier: identifier) { rule, _ in
            if let rule { completion(rule, nil) }
            else { store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json, completionHandler: completion) }
        }
    }
}

struct ReadableWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var session: WebReadingSession
    var blockAds = true

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.allowsBackForwardNavigationGestures = true
        view.uiDelegate = context.coordinator
        view.navigationDelegate = context.coordinator
        context.coordinator.session = session
        session.webView = view
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        session.webView = view
        guard context.coordinator.requestedURL != url || context.coordinator.blockAds != blockAds else { return }
        let destination = context.coordinator.requestedURL == url ? (view.url ?? url) : url
        context.coordinator.requestedURL = url
        context.coordinator.blockAds = blockAds
        context.coordinator.generation += 1
        let generation = context.coordinator.generation
        let navigationEpoch = context.coordinator.navigationEpoch
        view.configuration.userContentController.removeAllContentRuleLists()
        WebAdvertisementRules.compile(enabled: blockAds) { [weak view, weak session, weak coordinator = context.coordinator] rule, error in
            guard let view, coordinator?.generation == generation else { return }
            // Installation is part of the same generation as navigation. A
            // late compilation cannot re-enable ads blocking after a toggle.
            if let rule { view.configuration.userContentController.add(rule) }
            if let error { session?.errorMessage = "广告规则未加载：\(error.localizedDescription)" }
            // An internal link/back action may have moved the visible browser
            // while the disk-backed rule compilation was suspended.
            if coordinator?.navigationEpoch == navigationEpoch { view.load(URLRequest(url: destination)) }
        }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.generation += 1
        view.stopLoading()
        view.uiDelegate = nil
        view.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        weak var session: WebReadingSession?
        var navigationEpoch: UInt64 = 0
        var requestedURL: URL?
        var blockAds = false
        var generation = 0
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            navigationEpoch &+= 1
            session?.documentDidStartLoading()
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.navigationType == .linkActivated { webView.load(navigationAction.request) }
            return nil
        }
    }
}

struct ExtractedArticleView: View {
    let article: SmartWebArticle
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text(article.title).font(.title2.bold())
                ForEach(Array(article.paragraphs.enumerated()), id: \.offset) { _, text in
                    Text(text).font(.system(size: 19)).lineSpacing(8).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.pagePadding)
        }
        .pageBackground()
    }
}
