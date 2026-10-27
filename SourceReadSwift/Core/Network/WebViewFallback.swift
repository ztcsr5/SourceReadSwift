import Foundation
import WebKit

/// One XHR/fetch response captured inside the page.
struct WebViewCapturedResource: Codable, Equatable {
    let url: String
    let body: String
}

@MainActor
final class WebViewFallback: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Result<String, SourceEngineError>, Never>?
    private var webView: WKWebView?
    private var delayTask: Task<Void, Never>?
    private var fallbackTimer: Task<Void, Never>?
    private let cookieStore: SourceCookieStore?
    private var javaScript: String?
    private var sourceRegex: String?
    private var overrideUrlRegex: String?

    init(cookieStore: SourceCookieStore? = nil) {
        self.cookieStore = cookieStore
    }

    /// Loads a page inside a headless WKWebView and returns the body a rule
    /// should parse.
    ///
    /// - Parameters:
    ///   - javaScript: `ruleContent.webJs`. Legado runs it after the page
    ///     finished; a non-empty string return value becomes the body, which
    ///     is how sources extract data from pages that render through JS.
    ///   - sourceRegex: `ruleContent.sourceRegex`. Legado sniffs XHR/fetch
    ///     responses and uses the first URL matching this regex as the body.
    ///     Without it, App-API sources return an empty HTML shell even though
    ///     the JSON arrived in a sub-request.
    ///   - overrideUrlRegex: navigations whose URL matches are cancelled.
    ///     Used by sources that redirect to an app store / ad page.
    func load(
        url: URL,
        delay: TimeInterval = 3,
        javaScript: String? = nil,
        sourceRegex: String? = nil,
        overrideUrlRegex: String? = nil
    ) async -> Result<String, SourceEngineError> {
        if SandboxEnvironment.isLiveContainer {
            return .failure(.network("沙盒环境（LiveContainer）不支持后台无头 WebKit 渲染，请在书源规则中关闭 webView 或使用内置网页登录"))
        }
        self.javaScript = javaScript?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.sourceRegex = sourceRegex?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.overrideUrlRegex = overrideUrlRegex?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                if Task.isCancelled {
                    self.finish(.failure(.network("WebView fallback cancelled")))
                    return
                }
                self.navigationDelay = max(0.25, min(delay, 30))
                let configuration = WKWebViewConfiguration()
                configuration.defaultWebpagePreferences.allowsContentJavaScript = true
                configuration.userContentController.addUserScript(Self.sniffingUserScript())
                let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667), configuration: configuration)
                webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"
                webView.navigationDelegate = self
                self.webView = webView
                webView.load(URLRequest(url: url))
                // A navigation delegate is not guaranteed to fire for a
                // malformed challenge page. Keep a bounded fallback timer so
                // diagnostics never hang forever waiting on WebKit.
                self.fallbackTimer = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    guard let self, !Task.isCancelled else { return }
                    self.finish(.failure(.network("WebView fallback timed out")))
                }
            }
        }, onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(.network("WebView fallback cancelled")))
            }
        })
    }

    private var navigationDelay: TimeInterval = 3

    private func syncCookies(from webView: WKWebView) async {
        guard let cookieStore else { return }
        let cookies = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        await cookieStore.storeWebViewCookies(cookies)
    }

    private func finish(_ result: Result<String, SourceEngineError>) {
        delayTask?.cancel()
        delayTask = nil
        fallbackTimer?.cancel()
        fallbackTimer = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        continuation?.resume(returning: result)
        continuation = nil
        webView = nil
        javaScript = nil
        sourceRegex = nil
        overrideUrlRegex = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        delayTask?.cancel()
        delayTask = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            // If the page is a Cloudflare / anti-bot challenge, poll until completed or timeout
            var attempts = 0
            var finalHtml = ""
            while attempts < 12, !Task.isCancelled {
                attempts += 1
                try? await Task.sleep(nanoseconds: UInt64(max(0.4, self.navigationDelay) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                let html = (try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String) ?? ""
                let lower = html.lowercased()
                let isChallenge = lower.contains("cf-browser-verification")
                    || lower.contains("just a moment")
                    || lower.contains("challenge-running")
                    || lower.contains("turnstile")
                    || lower.contains("cf-challenge")
                if !isChallenge && !html.isEmpty {
                    finalHtml = html
                    break
                }
                finalHtml = html
            }

            // webJs runs after the page is settled. Legado lets it return the
            // extracted payload directly; JSON-string results are unwrapped.
            var scriptResult: String?
            if let script = self.javaScript {
                let value = try? await webView.evaluateJavaScript(script)
                scriptResult = Self.stringValue(fromJavaScript: value)
            }

            // Resource sniffing: prefer a captured XHR/fetch body whose URL
            // matches sourceRegex. This is what makes App-API sources work.
            if let sourceRegex = self.sourceRegex {
                let capturedJSON = (try? await webView.evaluateJavaScript(
                    "JSON.stringify(window.__sourcereadResources || [])"
                ) as? String) ?? "[]"
                let resources = Self.capturedResources(from: capturedJSON)
                if let body = Self.firstBody(in: resources, matching: sourceRegex) {
                    await self.syncCookies(from: webView)
                    self.finish(.success(body))
                    return
                }
            }

            await self.syncCookies(from: webView)
            if let scriptResult, !scriptResult.isEmpty {
                self.finish(.success(scriptResult))
            } else {
                self.finish(.success(finalHtml))
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(.network(error.localizedDescription)))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let regex = overrideUrlRegex,
           let url = navigationAction.request.url?.absoluteString,
           Self.matches(url, regex: regex) {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: - Resource sniffing (testable without WebKit)

    /// Injected at document start. Records XHR/fetch responses so the host can
    /// return the JSON/HTML an App-API source fetches after page load.
    static func sniffingUserScript() -> WKUserScript {
        WKUserScript(source: sniffingSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    static let sniffingSource = """
    (function () {
      if (window.__sourcereadResources) { return; }
      window.__sourcereadResources = [];
      function record(url, body) {
        try {
          if (typeof body !== 'string' || body.length === 0) { return; }
          window.__sourcereadResources.push({ url: String(url || ''), body: body });
          if (window.__sourcereadResources.length > 20) {
            window.__sourcereadResources.shift();
          }
        } catch (e) {}
      }
      try {
        var originalOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function (method, url) {
          try { this.__sourcereadURL = url; } catch (e) {}
          return originalOpen.apply(this, arguments);
        };
        var originalSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.send = function () {
          var xhr = this;
          try {
            xhr.addEventListener('load', function () {
              try {
                var type = xhr.responseType;
                if (type === '' || type === 'text') {
                  record(xhr.__sourcereadURL, xhr.responseText);
                } else if (type === 'json') {
                  record(xhr.__sourcereadURL, JSON.stringify(xhr.response));
                }
              } catch (e) {}
            });
          } catch (e) {}
          return originalSend.apply(this, arguments);
        };
      } catch (e) {}
      try {
        if (window.fetch) {
          var originalFetch = window.fetch;
          window.fetch = function (input, init) {
            var url = typeof input === 'string' ? input : ((input && input.url) || '');
            return originalFetch.apply(this, arguments).then(function (response) {
              try {
                var clone = response.clone();
                clone.text().then(function (text) { record(url, text); }).catch(function () {});
              } catch (e) {}
              return response;
            });
          };
        }
      } catch (e) {}
    })();
    """

    /// Decodes the JSON array produced by `sniffingSource`.
    static func capturedResources(from json: String) -> [WebViewCapturedResource] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([WebViewCapturedResource].self, from: data)) ?? []
    }

    /// First captured body whose URL matches `regex`.
    static func firstBody(in resources: [WebViewCapturedResource], matching regex: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: regex, options: [.caseInsensitive]) else {
            return nil
        }
        for resource in resources {
            let range = NSRange(location: 0, length: resource.url.utf16.count)
            if expression.firstMatch(in: resource.url, options: [], range: range) != nil {
                return resource.body
            }
        }
        return nil
    }

    static func matches(_ text: String, regex: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: regex, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(location: 0, length: text.utf16.count)
        return expression.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func stringValue(fromJavaScript value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let dictionary as [String: Any]:
            guard JSONSerialization.isValidJSONObject(dictionary),
                  let data = try? JSONSerialization.data(withJSONObject: dictionary),
                  let string = String(data: data, encoding: .utf8) else {
                return nil
            }
            return string
        case let array as [Any]:
            guard JSONSerialization.isValidJSONObject(array),
                  let data = try? JSONSerialization.data(withJSONObject: array),
                  let string = String(data: data, encoding: .utf8) else {
                return nil
            }
            return string
        default:
            return nil
        }
    }
}
