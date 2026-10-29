import Foundation

/// Cookie helpers shared by URLSession, the synchronous JavaScript bridge and
/// the persistent Legado state.  HTTP allows commas inside Expires attributes,
/// so a plain `split(",")` corrupts a combined Set-Cookie header.
enum CookieHeaderParser {
    /// Splits one or more Set-Cookie values while preserving commas in
    /// `Expires=Wed, 21 Oct 2015 07:28:00 GMT`.
    static func splitSetCookie(_ raw: String) -> [String] {
        let characters = Array(raw)
        guard !characters.isEmpty else { return [] }
        var result: [String] = []
        var start = 0
        var index = 0
        while index < characters.count {
            if characters[index] == "," {
                let remainder = characters[(index + 1)...]
                let candidate = remainder.drop(while: { $0.isWhitespace })
                // A comma starts the next cookie only when the following
                // token looks like `name=value`; Expires commas are followed
                // by a date token instead.
                if let equals = candidate.firstIndex(of: "="), equals > candidate.startIndex {
                    let name = candidate[..<equals]
                    if name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) {
                        let piece = String(characters[start..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !piece.isEmpty { result.append(piece) }
                        start = index + 1
                    }
                }
            }
            index += 1
        }
        let tail = String(characters[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    /// Extracts the first `name=value` pair from a Set-Cookie value.
    static func cookiePair(fromSetCookie value: String) -> (name: String, value: String)? {
        let pair = value.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        guard let equals = pair.firstIndex(of: "=") else { return nil }
        let name = pair[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
        let cookieValue = pair[pair.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return (String(name), String(cookieValue))
    }

    /// Parses a Cookie request header into name/value pairs.
    static func pairs(fromCookieHeader header: String) -> [(name: String, value: String)] {
        header.split(separator: ";", omittingEmptySubsequences: true).compactMap { part in
            cookiePair(fromSetCookie: String(part))
        }
    }

    /// Merges cookies by name; later values replace earlier values while
    /// unrelated cookies remain available to subsequent source requests.
    static func merge(_ incoming: String, into existing: String?) -> String {
        var merged: [(name: String, value: String)] = pairs(fromCookieHeader: existing ?? "")
        let incomingPairs: [(name: String, value: String)] = incoming.contains(",")
            ? splitSetCookie(incoming).compactMap { cookiePair(fromSetCookie: $0) }
            : pairs(fromCookieHeader: incoming)
        for pair in incomingPairs {
            merged.removeAll { $0.name.caseInsensitiveCompare(pair.name) == .orderedSame }
            merged.append(pair)
        }
        return merged.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    /// Foundation only parses RFC 1123 expiry dates.  Several novel sites
    /// emit `expires=Thu, 29-Oct-2026 17:10:52 GMT`, which Foundation silently
    /// drops; the cookie is then stored as a session cookie and a 30-second
    /// search cooldown turns into a permanent block.  Parse the attributes
    /// ourselves so the expiry survives.
    static func expiryDate(fromSetCookie value: String) -> Date? {
        var maxAge: TimeInterval?
        var expires: Date?
        for attribute in value.split(separator: ";", omittingEmptySubsequences: true).dropFirst() {
            let parts = attribute.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let raw = parts[1].trimmingCharacters(in: .whitespaces)
            switch name {
            case "max-age":
                if let seconds = TimeInterval(raw) { maxAge = seconds }
            case "expires":
                expires = parseCookieDate(raw)
            default:
                break
            }
        }
        if let maxAge { return Date(timeIntervalSinceNow: maxAge) }
        return expires
    }

    private static func parseCookieDate(_ raw: String) -> Date? {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEE, dd-MMM-yyyy HH:mm:ss zzz",
            "dd-MMM-yyyy HH:mm:ss zzz",
            "EEE, dd-MMM-yy HH:mm:ss zzz",
            "EEE MMM d HH:mm:ss yyyy"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    static func setCookieValues(from headers: [String: String]) -> [String] {
        headers.first { key, _ in key.caseInsensitiveCompare("Set-Cookie") == .orderedSame }
            .map { splitSetCookie($0.value) } ?? []
    }
}
