import Foundation

/// Reads literal export declarations from a known Legado updater without running its page.
enum SourcePublisherUpdateManifest {
    private static let declaration = try! NSRegularExpression(
        pattern: #"\bconst\s+serverConfig\s*=\s*\{([\s\S]{1,16384}?)^\s*\}\s*;"#,
        options: [.anchorsMatchLines]
    )
    private static let rowPattern = try! NSRegularExpression(
        pattern: #"(?:^|,)\s*[A-Za-z_]\w*\s*:\s*\{([^{}]{1,3072})\}\s*(?=,|$)"#
    )
    private static let fieldPattern = try! NSRegularExpression(
        pattern: #"^\s*(name|icon|baseUrl|downloadPath)\s*:\s*(['"])([^\r\n\\]{1,1024}?)\2\s*$"#
    )
    private static let maximumLinks = 16

    /// nil means unrecognized; an empty result means recognized but no safe literal exports.
    static func importLinks(in script: String) -> [SourcePublisherLink]? {
        guard script.contains("Object.values(serverConfig).map"),
              script.contains("server.baseUrl + server.downloadPath"),
              script.contains("yuedu://booksource/importonline?src=${encodeURIComponent(fullUrl)}") else { return nil }
        guard let match = declaration.firstMatch(in: script, range: NSRange(script.startIndex..., in: script)),
              let block = capture(match, group: 1, in: script) else { return [] }
        var seen = Set<URL>()
        return rowPattern.matches(in: block, range: NSRange(block.startIndex..., in: block))
            .prefix(maximumLinks).compactMap { match in
                guard let row = capture(match, group: 1, in: block), let link = parseRow(row),
                      seen.insert(link.url).inserted else { return nil }
                return link
            }
    }

    private static func parseRow(_ row: String) -> SourcePublisherLink? {
        var fields: [String: String] = [:]
        for field in row.split(separator: ",") {
            let item = String(field)
            guard let match = fieldPattern.firstMatch(in: item, range: NSRange(item.startIndex..., in: item)),
                  let key = capture(match, group: 1, in: item), let quote = capture(match, group: 2, in: item),
                  let value = capture(match, group: 3, in: item), !value.contains(quote),
                  fields.updateValue(value, forKey: key) == nil else { return nil }
        }
        guard let name = fields["name"], let base = fields["baseUrl"], let path = fields["downloadPath"],
              let url = exportURL(base: base, path: path) else { return nil }
        return SourcePublisherLink(title: String(name.prefix(120)), url: url, isPageReference: false)
    }

    private static func exportURL(base: String, path: String) -> URL? {
        guard let origin = SourcePublisherLinks.secureWebURL(base), origin.query == nil, origin.fragment == nil,
              let decoded = path.removingPercentEncoding, decoded.hasPrefix("/"), !decoded.hasPrefix("//"),
              decoded.rangeOfCharacter(from: .controlCharacters) == nil,
              !["\\", "?", "#"].contains(where: { decoded.contains($0) }),
              !decoded.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
              let url = SourcePublisherLinks.secureWebURL(SourceRequestBuilder.percentEncodePreservingExistingEscapes(base + path)),
              url.host == origin.host, url.port == origin.port,
              ["json", "xbs"].contains(url.pathExtension.lowercased()) else { return nil }
        return url
    }

    private static func capture(_ match: NSTextCheckingResult, group: Int, in text: String) -> String? {
        Range(match.range(at: group), in: text).map { String(text[$0]) }
    }
}
