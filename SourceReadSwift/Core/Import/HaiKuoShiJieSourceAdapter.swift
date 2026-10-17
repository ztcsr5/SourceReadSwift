import Foundation

/// Adapter for HaiKuoShiJie (海阔视界) book and content source formats.
/// Parses HaiKuo JSON rule exports and maps them into standard Legado `BookSource` models.
public struct HaiKuoShiJieSourceAdapter: Sendable {

    /// JS bridge code that can be injected into WKWebView to listen for HaiKuo rule imports.
    public static let webInjectionScript = """
    window.fy_bridge_app = {
        importRule: function(obj) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.haikuoImportRule) {
                window.webkit.messageHandlers.haikuoImportRule.postMessage(JSON.stringify(obj));
            }
        }
    };
    """

    // MARK: - Format Detection

    public static func isHaiKuoJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return false }
        
        // Characteristic keys for HaiKuo sources
        let hasTitleAndUrl = trimmed.contains("\"title\"") && trimmed.contains("\"url\"")
        let hasHaiKuoIdentifiers = trimmed.contains("\"find_rule\"") ||
            trimmed.contains("\"search_rule\"") ||
            trimmed.contains("\"fy_bridge_app\"") ||
            trimmed.contains("\"col_type\"") ||
            trimmed.contains("\"group\"") && trimmed.contains("\"海阔")
        
        return hasTitleAndUrl && hasHaiKuoIdentifiers
    }

    public static func isHaiKuoData(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return isHaiKuoJSON(text)
    }

    // MARK: - Import & Conversion

    public static func importSources(from text: String) -> [BookSource] {
        guard let data = text.data(using: .utf8) else { return [] }
        return importSources(from: data)
    }

    public static func importSources(from data: Data) -> [BookSource] {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        if let dictList = jsonObject as? [[String: Any]] {
            return dictList.compactMap { adapt(dict: $0) }
        } else if let singleDict = jsonObject as? [String: Any] {
            if let adapted = adapt(dict: singleDict) {
                return [adapted]
            }
        }
        return []
    }

    public static func adapt(dict: [String: Any]) -> BookSource? {
        let title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "海阔视界源"

        let url = (dict["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? ""
        guard !url.isEmpty else { return nil }

        let group = (dict["group"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "海阔导入"

        let searchUrl = dict["search_url"] as? String ?? dict["searchUrl"] as? String

        // Search rule extraction
        var searchFields: [String: String] = [:]
        if let searchRule = dict["search_rule"] as? String {
            searchFields["bookList"] = searchRule
            searchFields["name"] = "title@text||a@text"
            searchFields["bookUrl"] = "a@href||url@text"
        }

        // Find/Explore rule extraction
        var exploreFields: [String: String] = [:]
        if let findRule = dict["find_rule"] as? String {
            exploreFields["bookList"] = findRule
            exploreFields["name"] = "title@text||a@text"
            exploreFields["bookUrl"] = "a@href||url@text"
        }

        // Header / UA
        let headerStr: String?
        if let ua = dict["ua"] as? String {
            headerStr = "{\"User-Agent\": \"\(ua)\"}"
        } else {
            headerStr = nil
        }

        return BookSource(
            bookSourceName: title,
            bookSourceUrl: url,
            bookSourceGroup: group,
            bookSourceType: 0,
            enabled: true,
            weight: 90,
            searchUrl: searchUrl,
            exploreUrl: dict["find_url"] as? String,
            ruleSearch: searchFields.isEmpty ? nil : SourceRule(fields: searchFields),
            ruleBookInfo: nil,
            ruleToc: nil,
            ruleContent: nil,
            ruleExplore: exploreFields.isEmpty ? nil : SourceRule(fields: exploreFields),
            header: headerStr
        )
    }
}
