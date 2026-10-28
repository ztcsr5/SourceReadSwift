import Foundation

struct SourceURLDirective: Equatable {
    var urlText: String
    var method: SourceHTTPMethod
    var headers: [String: String]
    var body: Data?
    var expectedCharset: String?
    var timeout: TimeInterval?
    /// Legado `UrlOption.webView` (AnalyzeUrl.kt L188).  Android only checks
    /// that the key is present, so `{"webView": false}` also forces WebKit;
    /// we keep the same rule for compatibility.
    var webView: Bool?
    /// Legado `UrlOption.webJs` (L189): JS run inside the rendered page.
    var webJs: String?
    /// Legado `UrlOption.js` (L190-194): JS run against the final URL string.
    var urlJavaScript: String?
    /// Legado `UrlOption.retry` (L187): extra transport attempts.
    var retry: Int?
    /// Legado `UrlOption.type` (L185): response kind (`json` / `html`).
    var responseType: String?

    init(
        urlText: String,
        method: SourceHTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil,
        expectedCharset: String? = nil,
        timeout: TimeInterval? = nil,
        webView: Bool? = nil,
        webJs: String? = nil,
        urlJavaScript: String? = nil,
        retry: Int? = nil,
        responseType: String? = nil
    ) {
        self.urlText = urlText
        self.method = method
        self.headers = headers
        self.body = body
        self.expectedCharset = expectedCharset
        self.timeout = timeout
        self.webView = webView
        self.webJs = webJs
        self.urlJavaScript = urlJavaScript
        self.retry = retry
        self.responseType = responseType
    }
}

struct SourceURLDirectiveParser {
    func parse(_ text: String) -> SourceURLDirective {
        var working = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if working.contains("{{cookie.") {
            working = working.replacingOccurrences(
                of: #"\{\{cookie\.[^}]*\}\}"#,
                with: "",
                options: .regularExpression
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var headers: [String: String] = [:]
        var method: SourceHTTPMethod = .get
        var body: Data?
        var expectedCharset: String?
        var timeout: TimeInterval?
        var webView: Bool?
        var webJs: String?
        var urlJavaScript: String?
        var retry: Int?
        var responseType: String?

        let directives = splitURLAndTrailingDirectives(working)
        working = directives.url
        if let headerText = directives.header {
            headers.merge(parseStringMap(headerText), uniquingKeysWith: { _, new in new })
        }
        if let bodyText = directives.body {
            body = Data(decodeEscapes(bodyText).utf8)
            method = .post
        }
        if let charsetText = directives.charset {
            expectedCharset = charsetText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }

        let split = splitURLAndJSONOptions(working)
        working = split.url
        while working.hasSuffix("|") || working.hasSuffix("#") {
            working = String(working.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let options = split.options {
            for key in ["headers", "header", "bookSourceHeader"] {
                headers.merge(parseHeadersOption(options[key]), uniquingKeysWith: { _, new in new })
            }
            if let methodText = firstString(in: options, keys: ["method", "httpMethod", "type"]),
               let parsedMethod = SourceHTTPMethod(rawValue: methodText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) {
                method = parsedMethod
            }
            if let bodyOption = firstValue(in: options, keys: ["body", "requestBody", "postBody", "data"]) {
                body = encodeBodyOption(bodyOption, headers: headers)
                if method == .get { method = .post }
            }
            expectedCharset = firstString(in: options, keys: ["charset", "encoding", "encode"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .nilIfEmpty
            if let rawTimeout = firstValue(in: options, keys: ["timeout", "timeoutMs", "connectTimeout"]),
               let parsed = timeoutSeconds(rawTimeout) {
                timeout = parsed
            }
            // Legado treats any present `webView` key as "use WebKit"
            // (`option.webView?.toString()?.isNotBlank() == true`).
            if options.keys.contains(where: { $0.caseInsensitiveCompare("webView") == .orderedSame }) {
                webView = true
            }
            webJs = firstString(in: options, keys: ["webJs", "webJS"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            urlJavaScript = firstString(in: options, keys: ["js"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            if let rawRetry = firstValue(in: options, keys: ["retry"]),
               let parsedRetry = integerValue(rawRetry),
               parsedRetry > 0 {
                retry = parsedRetry
            }
            // `type` is also accepted as a method alias above; only keep it as
            // a response kind when it is not a valid HTTP verb.
            if let typeText = firstString(in: options, keys: ["type"]) {
                let trimmedType = typeText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedType.isEmpty,
                   SourceHTTPMethod(rawValue: trimmedType.uppercased()) == nil {
                    responseType = trimmedType
                }
            }
        }

        return SourceURLDirective(
            urlText: working,
            method: method,
            headers: headers,
            body: body,
            expectedCharset: expectedCharset,
            timeout: timeout,
            webView: webView,
            webJs: webJs,
            urlJavaScript: urlJavaScript,
            retry: retry,
            responseType: responseType
        )
    }

    private func splitURLAndTrailingDirectives(_ text: String) -> (url: String, header: String?, body: String?, charset: String?) {
        var markers: [(name: String, range: Range<String.Index>)] = []
        let aliases: [(name: String, marker: String)] = [
            ("header", "@Header:"),
            ("header", "@Headers:"),
            ("body", "@Body:"),
            ("body", "@Post:"),
            ("body", "@RequestBody:"),
            ("charset", "@Charset:"),
            ("charset", "@Encoding:")
        ]
        for alias in aliases {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text.range(
                    of: alias.marker,
                    options: .caseInsensitive,
                    range: searchStart..<text.endIndex
                  ) {
                markers.append((alias.name, range))
                searchStart = range.upperBound
            }
        }
        markers.sort { $0.range.lowerBound < $1.range.lowerBound }

        guard let first = markers.first else {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), nil, nil, nil)
        }

        var header: String?
        var body: String?
        var charset: String?
        for index in markers.indices {
            let marker = markers[index]
            let contentStart = marker.range.upperBound
            let nextIndex = markers.index(after: index)
            let contentEnd: String.Index
            if nextIndex < markers.endIndex {
                contentEnd = markers[nextIndex].range.lowerBound
            } else {
                contentEnd = text.endIndex
            }
            let content = String(text[contentStart..<contentEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            if marker.name == "header" {
                header = content
            } else if marker.name == "body" {
                body = content
            } else {
                charset = content
            }
        }

        let url = String(text[..<first.range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (url, header, body, charset)
    }

    private func splitURLAndJSONOptions(_ text: String) -> (url: String, options: [String: Any]?) {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = original.lowercased()
        // A JavaScript rule can itself contain `,{...}` (java.connect(url,{})).
        // Splitting there would cut the script in half, so leave it alone.
        if lower.hasPrefix("@js:") || lower.hasPrefix("<js>") || lower.hasPrefix("js:") {
            return (original, nil)
        }
        guard let jsonStartRange = text.range(of: #",\s*\{"#, options: .regularExpression) else {
            return (original, nil)
        }
        let url = String(text[..<jsonStartRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rawOptions = String(text[jsonStartRange.lowerBound...].dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)

        // Sources write `{...};`, `{...}` + backtick or `{...}` followed by a
        // whole `@js:` script. Feeding that tail to JSONSerialization failed
        // and the options were dropped, so the search went out as a bodyless
        // GET. Take the first balanced object and ignore the tail.
        guard let objectText = Self.firstBalancedObject(in: rawOptions) else {
            return (url, nil)
        }
        if let options = parseOptionsObject(objectText) {
            return (url, options)
        }
        return (url, nil)
    }

    private func parseOptionsObject(_ text: String) -> [String: Any]? {
        if let data = text.data(using: .utf8),
           let options = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return options
        }
        let sanitized = sanitizeRelaxedJSON(text)
        if let data = sanitized.data(using: .utf8),
           let options = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return options
        }
        if let options = evaluateJSObjectLiteral(text) {
            return options
        }
        return nil
    }

    /// First balanced `{...}` block, quote-aware. Returns nil when the block
    /// never closes (a JS fragment rather than an option object).
    static func firstBalancedObject(in text: String) -> String? {
        var depth = 0
        var quote: Character?
        var escaped = false
        var start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            if let active = quote {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == active {
                    quote = nil
                }
            } else {
                switch ch {
                case "\"", "'":
                    quote = ch
                case "{":
                    if depth == 0 { start = index }
                    depth += 1
                case "}":
                    if depth > 0 {
                        depth -= 1
                        if depth == 0, let begin = start {
                            return String(text[begin...index])
                        }
                    }
                default:
                    break
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// String-level repair for the JSON-ish objects Legado sources use:
    /// single quotes, single-quoted JSON bodies, bare keys, trailing commas
    /// and the occasional mismatched closing quote. Everything is converted
    /// to valid JSON so JSONSerialization does the actual parsing.
    private func sanitizeRelaxedJSON(_ raw: String) -> String {
        var converted = convertSingleQuotedStrings(raw)
        converted = quoteBareKeys(converted)
        converted = converted.replacingOccurrences(
            of: #",\s*([}\]])"#,
            with: "$1",
            options: .regularExpression
        )
        return converted.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func convertSingleQuotedStrings(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count + 16)
        var index = text.startIndex
        var inDouble = false
        var inSingle = false
        var escaped = false
        while index < text.endIndex {
            let ch = text[index]
            if inDouble {
                output.append(ch)
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inDouble = false
                }
            } else if inSingle {
                if escaped {
                    if ch == "'" {
                        output.append("'")
                    } else {
                        output.append("\\")
                        output.append(ch)
                    }
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "'" {
                    output.append("\"")
                    inSingle = false
                } else if ch == "\"" {
                    output.append("\\\"")
                } else if ch == "\n" || ch == "\r" {
                    // An unterminated single-quoted value ends at the line.
                    output.append("\"")
                    output.append(ch)
                    inSingle = false
                } else {
                    output.append(ch)
                }
            } else {
                if ch == "\"" {
                    inDouble = true
                    output.append(ch)
                } else if ch == "'" {
                    inSingle = true
                    output.append("\"")
                } else {
                    output.append(ch)
                }
            }
            index = text.index(after: index)
        }
        if inSingle { output.append("\"") }
        return output
    }

    private func quoteBareKeys(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count + 16)
        var index = text.startIndex
        var inString = false
        var escaped = false
        var lastSignificant: Character = "{"
        while index < text.endIndex {
            let ch = text[index]
            if inString {
                output.append(ch)
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
                index = text.index(after: index)
                continue
            }
            if ch == "\"" {
                inString = true
                output.append(ch)
                lastSignificant = ch
                index = text.index(after: index)
                continue
            }
            let isKeyPosition = (lastSignificant == "{" || lastSignificant == ",")
            let isIdentifierStart = ch.isLetter || ch == "_" || ch == "$"
            if isKeyPosition, isIdentifierStart {
                var end = index
                var identifier = ""
                while end < text.endIndex {
                    let c = text[end]
                    if c.isLetter || c.isNumber || c == "_" || c == "-" || c == "$" {
                        identifier.append(c)
                        end = text.index(after: end)
                    } else {
                        break
                    }
                }
                var lookahead = end
                while lookahead < text.endIndex, text[lookahead] == " " || text[lookahead] == "\t" {
                    lookahead = text.index(after: lookahead)
                }
                if lookahead < text.endIndex, text[lookahead] == ":" {
                    output.append("\"" + identifier + "\"")
                    index = end
                    continue
                }
            }
            if ch == " " || ch == "\n" || ch == "\r" || ch == "\t" {
                output.append(ch)
            } else {
                output.append(ch)
                lastSignificant = ch
            }
            index = text.index(after: index)
        }
        return output
    }

    private func evaluateJSObjectLiteral(_ raw: String) -> [String: Any]? {
        let runtime = JSCoreRuntime()
        let script = "try { JSON.stringify(eval('(' + \(raw.debugDescription) + ')')); } catch(e) { '' }"
        if case .success(let jsonString) = runtime.evaluate(script),
           !jsonString.isEmpty,
           let data = jsonString.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict
        }
        return nil
    }

    private func parseStringMap(_ text: String) -> [String: String] {
        let trimmed = decodeEscapes(text).trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return stringMap(object)
        }
        let relaxed = sanitizeRelaxedJSON(trimmed)
        if let data = relaxed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return stringMap(object)
        }
        let pairs = trimmed
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == ";" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        return pairs.reduce(into: [:]) { result, line in
            let separator: Character = line.contains(":") ? ":" : "="
            let parts = line.split(separator: separator, maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            var key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            while key.hasPrefix("{") || key.hasPrefix("\"") || key.hasPrefix("'") {
                key = String(key.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            while key.hasSuffix("}") || key.hasSuffix("\"") || key.hasSuffix("'") {
                key = String(key.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            while value.hasPrefix("\"") || value.hasPrefix("'") {
                value = String(value.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            while value.hasSuffix("}") || value.hasSuffix("\"") || value.hasSuffix("'") {
                value = String(value.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !key.isEmpty else { return }
            result[key] = decodeEscapes(value)
        }
    }

    private func parseHeadersOption(_ value: Any?) -> [String: String] {
        if let object = value as? [String: Any] {
            return stringMap(object)
        }
        if let text = value as? String {
            return parseStringMap(text)
        }
        return [:]
    }

    private func stringMap(_ object: [String: Any]) -> [String: String] {
        object.reduce(into: [:]) { result, item in
            var cleanKey = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            while cleanKey.hasPrefix("{") || cleanKey.hasPrefix("\"") || cleanKey.hasPrefix("'") {
                cleanKey = String(cleanKey.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            while cleanKey.hasSuffix("}") || cleanKey.hasSuffix("\"") || cleanKey.hasSuffix("'") {
                cleanKey = String(cleanKey.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !cleanKey.isEmpty else { return }
            result[cleanKey] = stringify(item.value)
        }
    }

    private func firstString(in options: [String: Any], keys: [String]) -> String? {
        firstValue(in: options, keys: keys) as? String
    }

    private func firstValue(in options: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = options[key] {
                return value
            }
        }
        return nil
    }

    private func encodeBodyOption(_ value: Any, headers: [String: String]) -> Data? {
        if let text = value as? String {
            return Data(decodeEscapes(text).utf8)
        }
        if let object = value as? [String: Any] {
            let contentType = headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value ?? ""
            if contentType.localizedCaseInsensitiveContains("application/json"),
               let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
                return data
            }
            let form = object
                .sorted { $0.key < $1.key }
                .map { key, value in
                    "\(urlEncode(key))=\(urlEncode(stringify(value)))"
                }
                .joined(separator: "&")
            return Data(form.utf8)
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            return data
        }
        return Data(stringify(value).utf8)
    }

    private func stringify(_ value: Any) -> String {
        if let value = value as? String { return decodeEscapes(value) }
        if let value = value as? NSNumber { return value.stringValue }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }

    private func integerValue(_ value: Any) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private func timeoutSeconds(_ value: Any) -> TimeInterval? {
        let number: Double?
        if let value = value as? NSNumber {
            number = value.doubleValue
        } else {
            number = Double(String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let number, number > 0 else { return nil }
        return number >= 100 ? number / 1_000 : number
    }

    private func decodeEscapes(_ value: String) -> String {
        guard value.contains("\\") else { return value }
        return value
            .replacingOccurrences(of: "\\r\\n", with: "\r\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "\r")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\'", with: "'")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
