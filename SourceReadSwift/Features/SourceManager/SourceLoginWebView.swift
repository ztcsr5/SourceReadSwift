import SwiftUI
import WebKit

struct SourceLoginWebView: UIViewRepresentable {
    let url: URL
    let cookieStore: SourceCookieStore
    let readingSession: WebReadingSession
    let cookieScope: SourceLoginCookieScope
    var onPageLoaded: (URL?) -> Void = { _ in }
    var onResponse: (Int, [String: String]) -> Void = { _, _ in }
    let onStatus: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(cookieStore: cookieStore, cookieScope: cookieScope, onPageLoaded: onPageLoaded, onResponse: onResponse, onStatus: onStatus)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = SourceBrowserUserAgent.value
        readingSession.webView = webView
        context.coordinator.readingSession = readingSession
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.load(url, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.loadTask?.cancel()
        coordinator.synchronizationTask?.cancel()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var readingSession: WebReadingSession?
        let cookieStore: SourceCookieStore
        let cookieScope: SourceLoginCookieScope
        let onPageLoaded: (URL?) -> Void
        let onResponse: (Int, [String: String]) -> Void
        let onStatus: (String) -> Void
        var loadTask: Task<Void, Never>?
        var synchronizationTask: Task<Void, Never>?

        init(cookieStore: SourceCookieStore, cookieScope: SourceLoginCookieScope,
             onPageLoaded: @escaping (URL?) -> Void, onResponse: @escaping (Int, [String: String]) -> Void,
             onStatus: @escaping (String) -> Void) {
            self.cookieStore = cookieStore
            self.cookieScope = cookieScope
            self.onPageLoaded = onPageLoaded
            self.onResponse = onResponse
            self.onStatus = onStatus
        }

        func load(_ url: URL, in webView: WKWebView) {
            cookieScope.recordVisit(to: url)
            loadTask = Task { @MainActor [weak webView] in
                let cookies = await cookieStore.allCookies()
                guard let webView, !Task.isCancelled else { return }
                for cookie in cookies {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                            continuation.resume()
                        }
                    }
                    guard !Task.isCancelled else { return }
                }
                webView.load(URLRequest(url: url))
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            cookieScope.recordVisit(to: webView.url)
            synchronizationTask?.cancel()
            readingSession?.documentDidStartLoading()
            onPageLoaded(nil)
            onStatus("正在加载…")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let finishedURL = webView.url
            cookieScope.recordVisit(to: finishedURL)
            synchronizationTask = Task { @MainActor [weak webView] in
                guard let webView else { return }
                do {
                    let count = try await SourceLoginBrowserCookies.synchronizePersistently(from: webView, into: cookieStore, scope: cookieScope)
                    guard !Task.isCancelled, webView.url == finishedURL, !webView.isLoading else { return }
                    onPageLoaded(finishedURL)
                    onStatus(count == 0 ? "页面已加载，请在网页内登录后点完成" : "页面已加载，登录信息已同步")
                } catch {
                    guard !Task.isCancelled, webView.url == finishedURL, !webView.isLoading else { return }
                    onPageLoaded(finishedURL)
                    onStatus(error.localizedDescription)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onStatus("页面加载失败：\(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onStatus("页面加载失败：\(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            cookieScope.recordVisit(to: navigationAction.request.url)
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.isForMainFrame {
                if let response = navigationResponse.response as? HTTPURLResponse {
                    var headers: [String: String] = [:]
                    for (key, value) in response.allHeaderFields { headers[String(describing: key)] = String(describing: value) }
                    onResponse(response.statusCode, headers)
                } else {
                    onResponse(200, ["Content-Type": "text/html; charset=utf-8"])
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            cookieScope.recordVisit(to: webView.url)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }
    }
}

@MainActor
final class SourceLoginCookieScope: ObservableObject {
    private(set) var visitedHosts: Set<String> = []

    func recordVisit(to url: URL?) {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased(), !host.isEmpty else { return }
        visitedHosts.insert(host)
    }
}

@MainActor
enum SourceLoginBrowserCookies {
    /// Completes only after the browser Cookie snapshot has been saved successfully.
    static func synchronizePersistently(from webView: WKWebView, into cookieStore: SourceCookieStore,
                                       scope: SourceLoginCookieScope? = nil) async throws -> Int {
        let count = await synchronize(from: webView, into: cookieStore, scope: scope)
        try Task.checkCancellation()
        try await cookieStore.requirePersistence()
        return count
    }

    /// Complete both stores before releasing a script that reads native CookieManager state.
    static func synchronize(from webView: WKWebView, into cookieStore: SourceCookieStore,
                            scope: SourceLoginCookieScope? = nil) async -> Int {
        scope?.recordVisit(to: webView.url)
        let visitedHosts = scope?.visitedHosts
        let cookies = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        guard !Task.isCancelled else { return 0 }
        if let visitedHosts {
            let selected = cookies.filter { SourceCookieStore.cookieMatchesVisitedHosts($0, hosts: visitedHosts) }
            await cookieStore.replaceWebViewCookies(selected, forVisitedHosts: visitedHosts)
            guard !Task.isCancelled else { return 0 }
            for cookie in HTTPCookieStorage.shared.cookies ?? []
                where SourceCookieStore.cookieMatchesVisitedHosts(cookie, hosts: visitedHosts) {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
            for cookie in selected { HTTPCookieStorage.shared.setCookie(cookie) }
            return selected.count
        }
        // Unscoped legacy callers may merge cookies, but cannot safely infer which absent cookies were deleted.
        for cookie in cookies { HTTPCookieStorage.shared.setCookie(cookie) }
        await cookieStore.storeWebViewCookies(cookies)
        return cookies.count
    }
}
