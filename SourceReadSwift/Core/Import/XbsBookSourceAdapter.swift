import Foundation

/// Adapter for XiangSeGuiGe (香色闺阁) .xbs book sources.
/// Performs XXTEA decryption, parses XBS JSON models, applies strict health/safety
/// filters (excluding video, comic, and dead/compromised domains), and maps rules into
/// standard `BookSource` instances.
public struct XbsBookSourceAdapter: Sendable {
    public static let defaultKey: [UInt8] = [
        0xe5, 0x87, 0xbc, 0xe8, 0xa4, 0x86, 0xe6, 0xbb,
        0xbf, 0xe9, 0x87, 0x91, 0xe6, 0xba, 0xa1, 0xe5
    ]

    private static let deadDomains: Set<String> = [
        "souhh.com",
        "souhh.net",
        "bqg999.cc"
    ]

    // MARK: - Format Detection

    public static func isXbsData(_ data: Data) -> Bool {
        if isEncryptedXbs(data) {
            return true
        }
        if let text = String(data: data, encoding: .utf8) {
            return isXbsJSON(text)
        }
        return false
    }

    public static func isEncryptedXbs(_ data: Data) -> Bool {
        guard data.count >= 16 else { return false }
        guard let sample = xxteaDecrypt(data: data.prefix(64), key: defaultKey) else {
            return false
        }
        if let str = String(data: sample, encoding: .utf8) {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
        }
        return false
    }

    public static func isXbsJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return false }
        return (trimmed.contains("\"searchBook\"") || trimmed.contains("\"chapterList\"") || trimmed.contains("\"chapterContent\""))
            && (trimmed.contains("\"parserID\"") || trimmed.contains("\"actionID\"") || trimmed.contains("\"miniAppVersion\"") || trimmed.contains("\"requestInfo\""))
    }

    // MARK: - XXTEA Decryption

    private static let delta: UInt32 = 0x9E3779B9

    public static func xxteaDecrypt(data: Data, key: [UInt8] = defaultKey) -> Data? {
        guard data.count >= 8 else { return nil }
        let n = data.count / 4
        guard n > 0 else { return nil }

        var v = [UInt32](repeating: 0, count: n)
        data.withUnsafeBytes { ptr in
            let u32Ptr = ptr.bindMemory(to: UInt32.self)
            for i in 0..<n {
                v[i] = CFSwapInt32LittleToHost(u32Ptr[i])
            }
        }

        var k = [UInt32](repeating: 0, count: 4)
        var paddedKey = key
        if paddedKey.count < 16 {
            paddedKey.append(contentsOf: [UInt8](repeating: 0, count: 16 - paddedKey.count))
        }
        paddedKey.prefix(16).withUnsafeBytes { ptr in
            let u32Ptr = ptr.bindMemory(to: UInt32.self)
            for i in 0..<4 {
                k[i] = CFSwapInt32LittleToHost(u32Ptr[i])
            }
        }

        let rounds = 6 + 52 / n
        var total = UInt32(truncatingIfNeeded: UInt64(rounds) * UInt64(delta))
        var y = v[0]

        for _ in 0..<rounds {
            let e = (total >> 2) & 3
            for p in (0..<n).reversed() {
                let z = v[(p > 0 ? p - 1 : n - 1)]
                let term1 = ((z >> 5) ^ (y << 2)) &+ ((y >> 3) ^ (z << 4))
                let term2 = (total ^ y) &+ (k[Int((UInt32(p) & 3) ^ e)] ^ z)
                let mx = term1 ^ term2
                v[p] = v[p] &- mx
                y = v[p]
            }
            total = total &- delta
        }

        var result = Data(capacity: n * 4)
        for i in 0..<n {
            var val = CFSwapInt32HostToLittle(v[i])
            withUnsafeBytes(of: &val) { result.append(contentsOf: $0) }
        }
        return result
    }

    // MARK: - Public Import & Conversion

    public static func importSources(from data: Data) -> [BookSource] {
        if isEncryptedXbs(data), let decrypted = xxteaDecrypt(data: data) {
            if let lastBrace = decrypted.range(of: Data("}".utf8), options: .backwards) {
                let validData = decrypted.subdata(in: 0..<lastBrace.upperBound)
                if let text = String(data: validData, encoding: .utf8) {
                    return importSources(from: text)
                }
            } else if let text = String(data: decrypted, encoding: .utf8) {
                return importSources(from: text)
            }
        }

        if let text = String(data: data, encoding: .utf8) {
            return importSources(from: text)
        }
        return []
    }

    public static func importSources(from jsonText: String) -> [BookSource] {
        guard let data = jsonText.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        if let dict = jsonObject as? [String: Any] {
            return adaptDictionary(dict)
        } else if let array = jsonObject as? [[String: Any]] {
            return array.compactMap { adaptSingleSource(name: $0["sourceName"] as? String ?? "", dict: $0) }
        }
        return []
    }

    // MARK: - Adaptation Logic

    private static func adaptDictionary(_ root: [String: Any]) -> [BookSource] {
        var results: [BookSource] = []
        if root["searchBook"] != nil || root["chapterList"] != nil || root["sourceUrl"] != nil {
            let name = (root["sourceName"] as? String) ?? "香色书源"
            if let source = adaptSingleSource(name: name, dict: root) {
                results.append(source)
            }
            return results
        }

        for (key, val) in root {
            guard let sourceDict = val as? [String: Any] else { continue }
            if let source = adaptSingleSource(name: key, dict: sourceDict) {
                results.append(source)
            }
        }
        return results.sorted { $0.weight > $1.weight }
    }

    public static func adaptSingleSource(name: String, dict: [String: Any]) -> BookSource? {
        let sourceName = ((dict["sourceName"] as? String)?.nilIfEmpty ?? name).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceName.isEmpty else { return nil }

        let sourceType = (dict["sourceType"] as? String ?? "").lowercased()
        let category = (dict["category"] as? String ?? "").lowercased()
        if sourceType == "video" || sourceType == "comic" || sourceType == "audio"
            || category == "video" || category == "comic" || category == "audio" {
            return nil
        }

        let searchBook = dict["searchBook"] as? [String: Any] ?? [:]
        let chapterList = dict["chapterList"] as? [String: Any] ?? [:]
        let chapterContent = dict["chapterContent"] as? [String: Any] ?? [:]
        let bookDetail = dict["bookDetail"] as? [String: Any] ?? [:]

        let host = (dict["sourceUrl"] as? String)?.nilIfEmpty
            ?? (searchBook["host"] as? String)?.nilIfEmpty
            ?? (chapterList["host"] as? String)?.nilIfEmpty
            ?? (chapterContent["host"] as? String)?.nilIfEmpty
            ?? ""
        guard !host.isEmpty else { return nil }

        for dead in deadDomains {
            if host.contains(dead) {
                return nil
            }
        }

        var headersDict: [String: String] = [:]
        if let topHeaders = dict["httpHeaders"] as? [String: Any] {
            for (k, v) in topHeaders {
                if let str = v as? String { headersDict[k] = str }
            }
        }
        if let searchHeaders = searchBook["httpHeaders"] as? [String: Any] {
            for (k, v) in searchHeaders {
                if let str = v as? String, headersDict[k] == nil { headersDict[k] = str }
            }
        }
        let headerString: String? = headersDict.isEmpty ? nil : (try? JSONSerialization.data(withJSONObject: headersDict).flatMap { String(data: $0, encoding: .utf8) })

        let searchUrl = buildSearchUrl(searchBook: searchBook, defaultHost: host)
        let ruleSearch = buildSearchRule(searchBook: searchBook)
        let (ruleBookInfo, ruleToc) = buildTocRules(
            searchBook: searchBook,
            bookDetail: bookDetail,
            chapterList: chapterList,
            host: host
        )
        let ruleContent = buildContentRule(chapterContent: chapterContent)

        let weightStr = (dict["weight"] as? String) ?? "\(dict["weight"] as? Int ?? 0)"
        let weight = Int(weightStr) ?? 0

        var raw: [String: String] = [:]
        raw["xbsOrigin"] = "true"
        raw["miniAppVersion"] = dict["miniAppVersion"] as? String ?? ""
        if let lastModify = dict["lastModifyTime"] as? String {
            raw["lastModifyTime"] = lastModify
        }

        return BookSource(
            bookSourceName: sourceName,
            bookSourceUrl: host,
            bookSourceGroup: "香色闺阁",
            bookSourceType: 0,
            enabled: true,
            weight: weight,
            searchUrl: searchUrl,
            exploreUrl: nil,
            ruleSearch: ruleSearch,
            ruleBookInfo: ruleBookInfo,
            ruleToc: ruleToc,
            ruleContent: ruleContent,
            ruleExplore: nil,
            header: headerString,
            loginUrl: nil,
            loginCheckJs: nil,
            customConfig: nil,
            raw: raw
        )
    }

    // MARK: - Component Builders

    private static func buildSearchUrl(searchBook: [String: Any], defaultHost: String) -> String? {
        guard let reqInfo = (searchBook["requestInfo"] as? String)?.nilIfEmpty
            ?? (searchBook["url"] as? String)?.nilIfEmpty else {
            return nil
        }

        let trimmed = reqInfo.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@js:") {
            let adaptedScript = trimmed
                .replacingOccurrences(of: "params.keyWord", with: "key")
                .replacingOccurrences(of: "params.pageIndex", with: "page")
            return adaptedScript
        }

        var fullUrl = trimmed
        if !fullUrl.lowercased().hasPrefix("http://") && !fullUrl.lowercased().hasPrefix("https://") {
            let base = defaultHost.hasSuffix("/") ? String(defaultHost.dropLast()) : defaultHost
            let path = fullUrl.hasPrefix("/") ? fullUrl : "/" + fullUrl
            fullUrl = base + path
        }

        fullUrl = fullUrl
            .replacingOccurrences(of: "%@keyWord", with: "{{key}}")
            .replacingOccurrences(of: "%@pageIndex", with: "{{page}}")

        if let method = (searchBook["httpMethod"] as? String)?.uppercased(), method == "POST" {
            let parts = fullUrl.split(separator: "?", maxSplits: 1)
            if parts.count == 2 {
                return "\(parts[0]),{\"method\":\"POST\",\"body\":\"\(parts[1])\"}"
            }
        }
        return fullUrl
    }

    private static func buildSearchRule(searchBook: [String: Any]) -> SourceRule? {
        guard !searchBook.isEmpty else { return nil }
        var fields: [String: String] = [:]
        if let list = searchBook["list"] as? String, !list.isEmpty {
            fields["bookList"] = list
        }
        if let name = searchBook["bookName"] as? String, !name.isEmpty {
            fields["name"] = name
        }
        if let author = searchBook["author"] as? String, !author.isEmpty {
            fields["author"] = author
        }
        if let detailUrl = searchBook["detailUrl"] as? String, !detailUrl.isEmpty {
            fields["bookUrl"] = detailUrl
        }
        if let cover = searchBook["cover"] as? String, !cover.isEmpty {
            fields["coverUrl"] = cover
        }
        if let desc = (searchBook["desc"] as? String)?.nilIfEmpty ?? (searchBook["intro"] as? String)?.nilIfEmpty {
            fields["intro"] = desc
        }
        if let cat = searchBook["cat"] as? String, !cat.isEmpty {
            fields["kind"] = cat
        }
        if let last = searchBook["lastChapterTitle"] as? String, !last.isEmpty {
            fields["lastChapter"] = last
        }
        return fields.isEmpty ? nil : SourceRule(fields: fields)
    }

    private static func buildTocRules(
        searchBook: [String: Any],
        bookDetail: [String: Any],
        chapterList: [String: Any],
        host: String
    ) -> (SourceRule?, SourceRule?) {
        var detailFields: [String: String] = [:]
        if let desc = bookDetail["desc"] as? String, !desc.isEmpty {
            detailFields["intro"] = desc
        }
        if let cover = bookDetail["cover"] as? String, !cover.isEmpty {
            detailFields["coverUrl"] = cover
        }
        if let status = bookDetail["status"] as? String, !status.isEmpty {
            detailFields["kind"] = status
        }
        if let last = bookDetail["lastChapterTitle"] as? String, !last.isEmpty {
            detailFields["lastChapter"] = last
        }

        if let reqInfo = chapterList["requestInfo"] as? String, !reqInfo.isEmpty {
            let trimmed = reqInfo.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("@js:") || trimmed.contains("${result}") || trimmed.contains("%@") {
                detailFields["tocUrl"] = trimmed.replacingOccurrences(of: "%@result", with: "${result}")
            }
        }

        var tocFields: [String: String] = [:]
        if let list = chapterList["list"] as? String, !list.isEmpty {
            tocFields["chapterList"] = list
        }
        if let title = chapterList["title"] as? String, !title.isEmpty {
            tocFields["chapterName"] = title
        }
        if let url = chapterList["url"] as? String, !url.isEmpty {
            tocFields["chapterUrl"] = url
        }
        if let next = chapterList["nextPageUrl"] as? String, !next.isEmpty {
            tocFields["nextTocUrl"] = next
        }

        let ruleBookInfo = detailFields.isEmpty ? nil : SourceRule(fields: detailFields)
        let ruleToc = tocFields.isEmpty ? nil : SourceRule(fields: tocFields)
        return (ruleBookInfo, ruleToc)
    }

    private static func buildContentRule(chapterContent: [String: Any]) -> SourceRule? {
        guard !chapterContent.isEmpty else { return nil }
        var fields: [String: String] = [:]
        if let content = chapterContent["content"] as? String, !content.isEmpty {
            fields["content"] = content
        }
        if let next = chapterContent["nextPageUrl"] as? String, !next.isEmpty {
            fields["nextContentUrl"] = next
        }
        return fields.isEmpty ? nil : SourceRule(fields: fields)
    }
}
