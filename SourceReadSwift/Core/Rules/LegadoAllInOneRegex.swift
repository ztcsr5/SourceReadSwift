import Foundation

/// Legado list-level AllInOne regex (`:pattern`).
///
/// Legado allows `bookList`, `chapterList` and `bookInfoInit` to start with
/// `:`; the rest of the rule is a regular expression that runs against the
/// whole response body. Every match contributes one row and the capture
/// groups are addressed from the field rules as `$1`, `$2`, ...
///
/// The common shape is group 1 = URL, group 2 = name:
/// `":href=\\"(/read[^\\"]*html)\\">([^<]*)"`. A leading `-` reverses the
/// rows (chapter lists that are rendered newest-first) and `+` is accepted as
/// a no-op marker.
enum LegadoAllInOneRegex {
    struct Rule: Equatable {
        let pattern: String
        let reversed: Bool
    }

    struct Row: Equatable {
        /// `groups[0]` is the whole match, `groups[1]` the first capture group.
        let groups: [String]

        var url: String { groups.indices.contains(1) ? groups[1].trimmingCharacters(in: .whitespacesAndNewlines) : "" }
        var name: String { groups.indices.contains(2) ? groups[2].trimmingCharacters(in: .whitespacesAndNewlines) : url }
    }

    /// Returns nil when the rule is not an AllInOne regex.
    static func rule(from raw: String) -> Rule? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var reversed = false
        if text.hasPrefix("-") {
            reversed = true
            text.removeFirst()
        } else if text.hasPrefix("+") {
            text.removeFirst()
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix(":") else { return nil }
        let pattern = String(text.dropFirst())
        guard !pattern.isEmpty else { return nil }
        return Rule(pattern: pattern, reversed: reversed)
    }

    static func rows(_ rule: Rule, body: String) -> [Row] {
        guard let regex = try? NSRegularExpression(
            pattern: rule.pattern,
            options: [.dotMatchesLineSeparators]
        ) else {
            return []
        }
        let nsBody = body as NSString
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: nsBody.length))
        var rows: [Row] = []
        rows.reserveCapacity(matches.count)
        for match in matches {
            var groups: [String] = []
            groups.reserveCapacity(match.numberOfRanges)
            for index in 0..<match.numberOfRanges {
                let range = match.range(at: index)
                groups.append(range.location == NSNotFound ? "" : nsBody.substring(with: range))
            }
            // A pattern without capture groups cannot address a URL/name.
            guard groups.count > 1 else { continue }
            rows.append(Row(groups: groups))
        }
        return rule.reversed ? Array(rows.reversed()) : rows
    }

    /// Resolves a field rule against one match: `$1`/`${1}`/`$0` address a
    /// capture group, `text` maps to the name group and `href`/`url` to the
    /// URL group. Empty rules fall back to the group the field normally uses.
    static func field(_ rawRule: String?, row: Row, defaultGroup: Int) -> String {
        let rule = (rawRule ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rule.isEmpty else {
            return row.groups.indices.contains(defaultGroup)
                ? row.groups[defaultGroup].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
        }
        if let index = captureIndex(rule), row.groups.indices.contains(index) {
            return row.groups[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        switch rule.lowercased() {
        case "text", "textnodes", "owntext":
            return row.name
        case "href", "src", "url":
            return row.url
        default:
            return ""
        }
    }

    private static func captureIndex(_ rule: String) -> Int? {
        var text = rule
        if text.hasPrefix("${"), text.hasSuffix("}") {
            text = String(text.dropFirst(2).dropLast())
        } else if text.hasPrefix("$") {
            text.removeFirst()
        } else {
            return nil
        }
        return Int(text)
    }
}
