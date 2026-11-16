import Foundation

struct SourceLoginInteraction: Sendable {
    let fields: [SourceLoginField]
    let destination: SourceLoginDestination?
    var persistenceWarning: String? = nil
}

/// These are requests for a user-visible handoff, not a login success result.
enum SourceLoginDestination: Equatable, Identifiable, Sendable {
    case web(URL, waitsForAndroidResult: Bool)
    case publisher([SourcePublisherLink])

    var id: String {
        switch self {
        case .web(let url, _): return url.absoluteString
        case .publisher(let links): return links.first?.id ?? "source-publisher"
        }
    }
}

enum SourceLoginBrowserAction {
    private static let maximumAddressBytes = 512 * 1024

    /// Capture a browser request only while executing a form button the user tapped.
    static func wrap(_ action: String, waitsInApp: Bool = false) -> String? {
        guard action.utf8.count <= 64 * 1024,
              let literal = try? JSONSerialization.data(
                withJSONObject: LegadoJavaScriptCompatibility.normalizeRuleScript(action), options: [.fragmentsAllowed]),
              let quoted = String(data: literal, encoding: .utf8) else { return nil }
        return """
        (function() {
          const originalOpen = java.startBrowser;
          const originalWait = java.startBrowserAwait;
          let pending = null;
          function capture(address, waitsForResult) {
            if (pending === null) {
              const text = String(address == null ? '' : address);
              pending = { address: text.length <= 524288 ? text : '', waitsForResult: waitsForResult };
            }
          }
          java.startBrowser = function(address) { capture(address, false); };
          java.startBrowserAwait = function(address, title) {
            if (\(waitsInApp ? "true" : "false")) return originalWait.apply(java, arguments);
            capture(address, true);
            throw new Error('Android synchronous browser result is unavailable on iOS');
          };
          try { (0, eval)(\(quoted)); }
          catch (error) { if (pending === null) throw error; }
          finally { java.startBrowser = originalOpen; java.startBrowserAwait = originalWait; }
          return JSON.stringify(pending || {});
        })()
        """
    }

    /// Decodes inert destinations. Publisher HTML is inspected for links, never rendered or executed.
    static func destination(from text: String) -> Result<SourceLoginDestination?, SourceEngineError> {
        guard let request = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            return .failure(.rule("书源操作没有返回有效状态"))
        }
        guard let address = request["address"] as? String else { return .success(nil) }
        guard address.utf8.count <= maximumAddressBytes, !address.isEmpty else {
            return .failure(.unsupported("书源给出的浏览器地址为空或过长"))
        }
        let waitsForResult = (request["waitsForResult"] as? Bool) == true
        if let url = loginWebURL(address) {
            return .success(.web(url, waitsForAndroidResult: waitsForResult))
        }
        if !waitsForResult, address.lowercased().hasPrefix("data:text/html;"),
           let url = URL(string: SourceRequestBuilder.percentEncodePreservingExistingEscapes(address)),
           case .success(let page) = SourceInlineEnvelope.response(for: url) {
            let links = SourcePublisherLinks.linksForSourceAction(in: page.body)
            if !links.isEmpty { return .success(.publisher(links)) }
            return .failure(.unsupported("版本页没有可用的 HTTPS 书源链接，请向作者取得更新版 JSON 再导入。"))
        }
        return .failure(.unsupported("书源没有提供可打开的 HTTP 或 HTTPS 登录页面。"))
    }

    /// Login pages may use explicit HTTP sources; publisher imports retain their separate HTTPS policy.
    static func loginWebURL(_ text: String) -> URL? {
        guard text.utf8.count <= 8_192, let url = URL(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
        return url
    }
}
