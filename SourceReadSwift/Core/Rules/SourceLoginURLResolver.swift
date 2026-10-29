import Foundation

/// Resolves a Legado `loginUrl` into a page the in-app browser can open.
///
/// The old implementation required an absolute `http(s)` URL. Many sources
/// declare a relative path (`/login.php`, `user/login`) or leave `loginUrl`
/// empty and expect the reader to log in on the source home page. Both cases
/// surfaced as the misleading "登录地址无效" screen.
enum SourceLoginURLResolver {
    struct Target: Equatable {
        let url: URL
        /// True when `loginUrl` was unusable and the source home page was used
        /// instead. The login sheet says so explicitly.
        let usedBookSourceFallback: Bool
    }

    static func resolve(source: BookSource) -> Target? {
        resolve(loginUrl: source.loginUrl, bookSourceUrl: source.networkBaseURL)
    }

    static func resolve(loginUrl: String?, bookSourceUrl: String?) -> Target? {
        let sourceBase = baseURL(bookSourceUrl)
        let raw = loginUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty {
            let expanded = expandTemplates(raw, bookSourceUrl: bookSourceUrl)
            if let target = targetURL(from: expanded, sourceBase: sourceBase) {
                return Target(url: target, usedBookSourceFallback: false)
            }
        }
        if let base = sourceBase {
            return Target(url: base, usedBookSourceFallback: true)
        }
        return nil
    }

    /// Legado sources occasionally write `{{bookSourceUrl}}/login` instead of a
    /// constant host. Expanding the handful of documented aliases is enough to
    /// make those sources usable; JavaScript expressions still fall through to
    /// the book-source home page.
    private static func expandTemplates(_ raw: String, bookSourceUrl: String?) -> String {
        guard raw.contains("{{") else { return raw }
        let base = bookSourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw
            .replacingOccurrences(of: "{{bookSourceUrl}}", with: base)
            .replacingOccurrences(of: "{{baseUrl}}", with: base)
            .replacingOccurrences(of: "{{sourceUrl}}", with: base)
            .replacingOccurrences(of: "{{host}}", with: base)
    }

    private static func targetURL(from raw: String, sourceBase: URL?) -> URL? {
        guard !raw.isEmpty, SourceLoginScript.dynamicUI(from: raw) == nil,
              !raw.contains(where: { $0.isWhitespace }),
              !raw.contains("{"), !raw.contains("}"),
              !raw.contains("("), !raw.contains(")"), !raw.contains(";") else { return nil }
        if raw.hasPrefix("//"), let url = URL(string: "https:" + raw), isHTTP(url) {
            return url
        }
        if let absolute = absoluteHTTPURL(raw) {
            return absolute
        }
        if !raw.contains("://"),
           !raw.hasPrefix("/"),
           !raw.hasPrefix("./"),
           !raw.hasPrefix("../"),
           let firstComponent = raw.split(separator: "/").first,
           firstComponent.contains("."),
           let prefixed = absoluteHTTPURL("https://" + raw) {
            return prefixed
        }
        if let base = sourceBase,
           let relative = URL(string: raw, relativeTo: base)?.absoluteURL,
           isHTTP(relative) {
            return relative
        }
        return nil
    }

    private static func absoluteHTTPURL(_ text: String) -> URL? {
        guard let url = URL(string: text), isHTTP(url) else { return nil }
        return url
    }

    private static func baseURL(_ text: String?) -> URL? {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let url = URL(string: raw), isHTTP(url) { return url }
        // Some imported sources omit the scheme.
        if let url = URL(string: "https://" + raw), isHTTP(url) { return url }
        return nil
    }

    private static func isHTTP(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }
}
