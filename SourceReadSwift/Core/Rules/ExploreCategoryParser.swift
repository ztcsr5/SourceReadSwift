import Foundation

struct ExploreCategory: Identifiable, Hashable, Sendable {
    var id: String { "\(group ?? "")_\(title)_\(url)" }
    let title: String
    let url: String
    let group: String?
    let style: [String: String]?

    init(title: String, url: String, group: String? = nil, style: [String: String]? = nil) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        self.group = group?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.style = style
    }
}

enum ExploreCategoryParser {
    static func parse(exploreUrl: String?) -> [ExploreCategory] {
        guard let raw = exploreUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return []
        }

        // 1. Check if the string is formatted as JSON (array of objects or items)
        if raw.hasPrefix("[") {
            if let categories = parseJSON(raw), !categories.isEmpty {
                return categories
            }
        }

        // 2. Parse text-based format (lines with ::, &&, etc.)
        return parseTextFormat(raw)
    }

    private static func parseJSON(_ jsonString: String) -> [ExploreCategory]? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        var result: [ExploreCategory] = []
        var currentGroup: String? = nil

        func processItem(_ item: Any) {
            if let dict = item as? [String: Any] {
                let title = (dict["title"] as? String ?? dict["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let url = (dict["url"] as? String ?? dict["path"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                // If url is empty, this item can be a section/group header
                if url.isEmpty && !title.isEmpty {
                    currentGroup = title
                    return
                }

                guard !title.isEmpty, !url.isEmpty else { return }

                var styleDict: [String: String] = [:]
                if let style = dict["style"] as? [String: Any] {
                    for (k, v) in style {
                        styleDict[k] = "\(v)"
                    }
                }

                result.append(ExploreCategory(
                    title: title,
                    url: url,
                    group: currentGroup,
                    style: styleDict.isEmpty ? nil : styleDict
                ))
            } else if let str = item as? String {
                let parts = str.components(separatedBy: "::")
                if parts.count >= 2 {
                    let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let url = parts.dropFirst().joined(separator: "::").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty && !url.isEmpty {
                        result.append(ExploreCategory(title: title, url: url, group: currentGroup))
                    }
                }
            }
        }

        if let array = json as? [Any] {
            for item in array {
                processItem(item)
            }
        }

        return result
    }

    private static func parseTextFormat(_ text: String) -> [ExploreCategory] {
        var result: [ExploreCategory] = []
        let lines = text.components(separatedBy: .newlines)
        var currentGroup: String? = nil

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("//"), !line.hasPrefix("#") else { continue }

            // Grouping with double ampersand e.g. "周榜&&月榜::url2" or "分类&&玄幻::url1&&都市::url2"
            if line.contains("&&") {
                let segments = line.components(separatedBy: "&&")
                for (idx, seg) in segments.enumerated() {
                    let trimmed = seg.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }

                    if trimmed.contains("::") {
                        let parts = trimmed.components(separatedBy: "::")
                        let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                        let url = parts.dropFirst().joined(separator: "::").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !title.isEmpty && !url.isEmpty {
                            result.append(ExploreCategory(title: title, url: url, group: currentGroup))
                        }
                    } else if idx == 0 {
                        // First segment without :: acts as group header
                        currentGroup = trimmed
                    }
                }
                continue
            }

            // Standard double colon line: "玄幻::/sort/1/{{page}}.html"
            if line.contains("::") {
                let parts = line.components(separatedBy: "::")
                let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let url = parts.dropFirst().joined(separator: "::").trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty && !url.isEmpty {
                    result.append(ExploreCategory(title: title, url: url, group: currentGroup))
                }
            } else {
                // Standalone header line e.g. [榜单] or 热门推荐
                var groupName = line
                if groupName.hasPrefix("[") && groupName.hasSuffix("]") {
                    groupName = String(groupName.dropFirst().dropLast())
                }
                currentGroup = groupName
            }
        }

        return result
    }
}
