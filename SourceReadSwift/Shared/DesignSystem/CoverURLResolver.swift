import Foundation

/// Normalises the many shapes a Legado source uses for a cover URL.
///
/// Protocol-relative (`//cdn.example.com/a.jpg`) and root-relative
/// (`/images/a.jpg`) covers are common in imported JSON sources. `URL(string:)`
/// accepts both as *relative* URLs, and `URLSession` then refuses to load them,
/// which is why the discover list could show a cover while the detail page and
/// shelf showed the placeholder for the same book.
enum CoverURLResolver {
    /// - Parameters:
    ///   - raw: cover value exactly as the source returned it.
    ///   - base: the detail/book URL, which may itself be relative.
    ///   - fallbackBase: the book-source home URL. Shelf records created by
    ///     older builds sometimes store a relative `bookURL`, so resolving the
    ///     detail URL against the source home page is what makes those covers
    ///     visible again.
    static func url(from raw: String?, base: String?, fallbackBase: String? = nil) -> URL? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if text.hasPrefix("//") {
            return URL(string: "https:" + text)
        }
        if let absolute = URL(string: text), absolute.scheme?.isEmpty == false {
            return absolute
        }
        let fallback = baseURL(from: fallbackBase)
        if let resolvedBase = baseURL(from: base, relativeTo: fallback) ?? fallback,
           let url = URL(string: text, relativeTo: resolvedBase)?.absoluteURL,
           url.scheme?.isEmpty == false {
            return url
        }
        return nil
    }

    private static func baseURL(from raw: String?, relativeTo parent: URL? = nil) -> URL? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if text.hasPrefix("//"), let url = URL(string: "https:" + text) { return url }
        if let url = URL(string: text), url.scheme?.isEmpty == false { return url }
        if let parent, let url = URL(string: text, relativeTo: parent)?.absoluteURL,
           url.scheme?.isEmpty == false {
            return url
        }
        if let first = text.split(separator: "/").first, first.contains("."),
           let url = URL(string: "https://" + text) {
            return url
        }
        // A bare host such as `localhost` has no dot; accept it only when the
        // value cannot be mistaken for a relative path.
        if !text.contains("/"), let url = URL(string: "https://" + text) {
            return url
        }
        return nil
    }
}
