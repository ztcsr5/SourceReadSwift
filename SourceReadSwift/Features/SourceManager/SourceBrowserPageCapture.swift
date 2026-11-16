import Foundation
import WebKit

/// Captures the user's current DOM without another request or exposing page content in diagnostics.
@MainActor
enum SourceBrowserPageCapture {
    enum CaptureError: LocalizedError {
        case pageChanged, oversized, unavailable

        var errorDescription: String? {
            switch self {
            case .pageChanged: return "网页仍在跳转，请等页面加载完成后再点完成。"
            case .oversized: return "网页内容超过 4 MiB，无法交给书源规则，请返回较小的结果页后重试。"
            case .unavailable: return "无法读取当前网页内容，请重新加载后再试。"
            }
        }
    }

    static func capture(from webView: WKWebView, statusCode: Int, headers: [String: String]) async throws -> SourceResponse {
        guard !webView.isLoading, let expectedURL = webView.url,
              SourceLoginBrowserAction.browserPageURL(expectedURL.absoluteString) != nil else { throw CaptureError.pageChanged }
        let snapshot: Any
        do {
            snapshot = try await webView.evaluateJavaScript("""
            (function() {
              var html = document.documentElement ? document.documentElement.outerHTML : '';
              if (html.length > 4194304) return {oversized: true};
              return {html: html, url: String(location.href)};
            })()
            """)
        } catch {
            throw CaptureError.unavailable
        }
        try Task.checkCancellation()
        guard let page = snapshot as? [String: Any] else { throw CaptureError.unavailable }
        if page["oversized"] as? Bool == true { throw CaptureError.oversized }
        guard let html = page["html"] as? String, let address = page["url"] as? String,
              let actualURL = SourceLoginBrowserAction.browserPageURL(address),
              webView.url == expectedURL, actualURL == expectedURL, !webView.isLoading else { throw CaptureError.pageChanged }
        let bytes = Data(html.utf8)
        guard bytes.count <= SourceBrowserLoginRequest.maximumResponseBytes else { throw CaptureError.oversized }
        return SourceResponse(url: actualURL, statusCode: statusCode, headers: headers, body: html, data: bytes)
    }
}
