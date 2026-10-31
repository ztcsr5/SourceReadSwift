import Foundation
import SwiftSoup

enum MediaURLResolver {
    /// Preserve signed query parameters when resolving relative CDN paths.
    static func resolve(_ raw: String, base: String) -> String? {
        let value = (try? Entities.unescape(raw)) ?? raw
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isNewline }),
              let url = URL(string: trimmed, relativeTo: URL(string: base))?.absoluteURL,
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              url.host != nil else { return nil }
        return url.standardized.absoluteString
    }
}
