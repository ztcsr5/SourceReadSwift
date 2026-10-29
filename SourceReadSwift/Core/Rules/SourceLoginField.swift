import Foundation

/// Legado `RowUi` (`app/src/main/java/io/legado/app/data/entities/rule/RowUi.kt`),
/// the schema behind `BaseSource.loginUi`.
///
/// Legado renders one row per entry: `text` / `password` collect input, and
/// `button` opens `action` in a browser.  `SourceLoginDialog` then hands the
/// collected `{name: value}` map to `source.login()`.
struct SourceLoginField: Equatable, Sendable, Identifiable {
    enum Kind: String, Sendable {
        case text
        case password
        case button
        case toggle
    }

    let name: String
    let type: Kind
    let action: String?
    let choices: [String]
    let defaultValue: String?

    var id: String { type.rawValue + ":" + name }

    init(name: String, type: Kind = .text, action: String? = nil, choices: [String] = [], defaultValue: String? = nil) {
        self.name = name
        self.type = type
        self.action = action
        self.choices = choices
        self.defaultValue = defaultValue
    }
}

enum SourceLoginFieldParser {
    /// Parses `loginUi`.  Legado stores the rows as a JSON array; some sources
    /// write relaxed JSON (single quotes / trailing commas) and a few write a
    /// bare object for a single field, all accepted here.
    static func parse(_ raw: String?) -> [SourceLoginField] {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return []
        }
        guard let objects = jsonObjects(text) ?? relaxedObjects(text) else { return [] }
        return objects.compactMap { object in
            guard let name = stringValue(object["name"] ?? object["title"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty else { return nil }
            let kind = SourceLoginField.Kind(
                rawValue: (stringValue(object["type"]) ?? "text")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            ) ?? .text
            let action = stringValue(object["action"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            let choices = (object["chars"] as? [Any])?.compactMap(stringValue) ?? []
            let defaultValue = stringValue(object["default"] ?? object["value"])
            return SourceLoginField(name: name, type: kind, action: action, choices: choices, defaultValue: defaultValue)
        }
    }

    private static func jsonObjects(_ text: String) -> [[String: Any]]? {
        guard let data = text.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        if let array = any as? [[String: Any]] { return array }
        if let object = any as? [String: Any] { return [object] }
        return nil
    }

    private static func relaxedObjects(_ text: String) -> [[String: Any]]? {
        var sanitized = text.replacingOccurrences(of: "'", with: "\"")
        sanitized = sanitized.replacingOccurrences(of: #",\s*\]"#, with: "]", options: .regularExpression)
        sanitized = sanitized.replacingOccurrences(of: #",\s*\}"#, with: "}", options: .regularExpression)
        return jsonObjects(sanitized)
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}

/// `BaseSource.getLoginJs()` (`BaseSource.kt` L36-45) plus the credential
/// namespace that `source.getLoginInfoMap()` reads in `JSCoreRuntime`.
enum SourceLoginScript {
    static let loginInfoPrefix = "source.login."

    static func loginInfoKey(_ name: String) -> String {
        loginInfoPrefix + name
    }

    /// A dynamic loginUi is a script, not malformed JSON or a login URL.
    static func dynamicUI(from raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.hasPrefix("@js:") || raw.lowercased().hasPrefix("<js>") else { return nil }
        return script(from: raw)
    }

    /// Strips the Legado `@js:` / `<js>…</js>` wrapper.  A source that leaves
    /// `loginUrl` empty has no script; its credentials are only stored.
    static func script(from loginUrl: String?) -> String? {
        guard let raw = loginUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("@js:") {
            return String(raw.dropFirst(4))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }
        if raw.lowercased().hasPrefix("<js>") {
            guard let end = raw.range(of: "</js>", options: .backwards) else { return nil }
            let start = raw.index(raw.startIndex, offsetBy: 4)
            guard start <= end.lowerBound else { return nil }
            return String(raw[start..<end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }
        return raw
    }

    /// A plain `http(s)` / protocol-relative / rooted path is a page the reader
    /// opens in the login WebView, not JavaScript.
    static func isPageURL(_ loginUrl: String?) -> Bool {
        guard let raw = loginUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return false
        }
        let lowered = raw.lowercased()
        if lowered.hasPrefix("@js:") || lowered.hasPrefix("<js>") { return false }
        // `// ==== config ====\nvar ...` is a JS comment, not a
        // protocol-relative URL. This previously disabled 木里/日落 login.
        if raw.contains(where: { $0.isWhitespace }) || raw.contains("{") || raw.contains("}") {
            return false
        }
        if lowered.hasPrefix("//") {
            guard let url = URL(string: "https:" + raw), let host = url.host,
                  !host.isEmpty, host != "." else { return false }
            return true
        }
        return lowered.hasPrefix("http://")
            || lowered.hasPrefix("https://")
            || lowered.hasPrefix("/")
    }
}
