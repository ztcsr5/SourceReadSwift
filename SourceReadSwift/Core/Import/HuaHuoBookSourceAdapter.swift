import Foundation

/// Adapter for HuaHuo (花火阅读) book source format.
/// Automatically detects and normalizes HuaHuo's specialized rule fields
/// (e.g., `exploreBookList`, `searchCoverUrl`, `infoTocUrl`, `nextContentUrl`)
/// into standard Legado `BookSource` models.
struct HuaHuoBookSourceAdapter: Sendable {

    // MARK: - Format Detection

    static func isHuaHuoJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return false }
        
        let hasHuaHuoRuleKeys = trimmed.contains("\"exploreBookList\"") ||
            trimmed.contains("\"searchBookList\"") ||
            trimmed.contains("\"infoName\"") ||
            trimmed.contains("\"infoTocUrl\"") ||
            trimmed.contains("\"infoCoverUrl\"") ||
            trimmed.contains("\"tocList\"") ||
            trimmed.contains("\"nextContentUrl\"")
        
        let hasRuleContainers = trimmed.contains("\"ruleSearch\"") ||
            trimmed.contains("\"ruleBookInfo\"") ||
            trimmed.contains("\"ruleToc\"") ||
            trimmed.contains("\"ruleContent\"") ||
            trimmed.contains("\"ruleExplore\"")

        return hasHuaHuoRuleKeys && hasRuleContainers
    }

    static func isHuaHuoData(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return isHuaHuoJSON(text)
    }

    // MARK: - Import & Conversion

    static func importSources(from text: String) -> [BookSource] {
        guard let data = text.data(using: .utf8) else { return [] }
        return importSources(from: data)
    }

    static func importSources(from data: Data) -> [BookSource] {
        let decoder = JSONDecoder()
        
        if let array = try? decoder.decode([HuaHuoRawSource].self, from: data) {
            return array.compactMap { adapt(raw: $0) }
        }
        
        if let single = try? decoder.decode(HuaHuoRawSource.self, from: data) {
            if let adapted = adapt(raw: single) {
                return [adapted]
            }
        }
        
        return []
    }

    static func adapt(raw: HuaHuoRawSource) -> BookSource? {
        let name = raw.sourceName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? raw.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "花火导入源"
        
        let url = raw.sourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? raw.url?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? ""
        guard !url.isEmpty else { return nil }

        let group = raw.sourceGroup?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "花火导入"

        // 1. ruleSearch
        var searchFields: [String: String] = [:]
        if let s = raw.ruleSearch {
            if let v = s.searchBookList?.nilIfEmpty { searchFields["bookList"] = v }
            if let v = s.searchName?.nilIfEmpty { searchFields["name"] = v }
            if let v = s.searchAuthor?.nilIfEmpty { searchFields["author"] = v }
            if let v = s.searchIntro?.nilIfEmpty { searchFields["intro"] = v }
            if let v = s.searchKind?.nilIfEmpty { searchFields["kind"] = v }
            if let v = s.searchLastChapter?.nilIfEmpty { searchFields["lastChapter"] = v }
            if let v = s.searchBookUrl?.nilIfEmpty { searchFields["bookUrl"] = v }
            if let v = s.searchCoverUrl?.nilIfEmpty { searchFields["coverUrl"] = v }
            if let v = s.searchWordCount?.nilIfEmpty { searchFields["wordCount"] = v }
        }

        // 2. ruleBookInfo
        var infoFields: [String: String] = [:]
        if let i = raw.ruleBookInfo {
            if let v = i.infoName?.nilIfEmpty { infoFields["name"] = v }
            if let v = i.infoAuthor?.nilIfEmpty { infoFields["author"] = v }
            if let v = i.infoIntro?.nilIfEmpty { infoFields["intro"] = v }
            if let v = i.infoKind?.nilIfEmpty { infoFields["kind"] = v }
            if let v = i.infoLastChapter?.nilIfEmpty { infoFields["lastChapter"] = v }
            if let v = i.infoUpdateTime?.nilIfEmpty { infoFields["updateTime"] = v }
            if let v = i.infoCoverUrl?.nilIfEmpty { infoFields["coverUrl"] = v }
            if let v = i.infoTocUrl?.nilIfEmpty { infoFields["tocUrl"] = v }
            if let v = i.infoWordCount?.nilIfEmpty { infoFields["wordCount"] = v }
        }

        // 3. ruleToc
        var tocFields: [String: String] = [:]
        if let t = raw.ruleToc {
            if let v = t.tocList?.nilIfEmpty { tocFields["chapterList"] = v }
            if let v = t.tocName?.nilIfEmpty { tocFields["chapterName"] = v }
            if let v = t.tocUrl?.nilIfEmpty { tocFields["chapterUrl"] = v }
            if let v = t.isVip?.nilIfEmpty { tocFields["isVip"] = v }
            if let v = t.tocUpdateTime?.nilIfEmpty { tocFields["updateTime"] = v }
            if let v = t.nextTocUrl?.nilIfEmpty { tocFields["nextTocUrl"] = v }
        }

        // 4. ruleContent
        var contentFields: [String: String] = [:]
        if let c = raw.ruleContent {
            if let v = c.content?.nilIfEmpty { contentFields["content"] = v }
            if let v = c.nextContentUrl?.nilIfEmpty { contentFields["nextContentUrl"] = v }
            if let v = c.webJs?.nilIfEmpty { contentFields["webJs"] = v }
            if let v = c.sourceRegex?.nilIfEmpty { contentFields["sourceRegex"] = v }
            if let v = c.replaceRegex?.nilIfEmpty { contentFields["replaceRegex"] = v }
        }

        // 5. ruleExplore
        var exploreFields: [String: String] = [:]
        if let e = raw.ruleExplore {
            if let v = e.exploreBookList?.nilIfEmpty { exploreFields["bookList"] = v }
            if let v = e.exploreName?.nilIfEmpty { exploreFields["name"] = v }
            if let v = e.exploreAuthor?.nilIfEmpty { exploreFields["author"] = v }
            if let v = e.exploreIntro?.nilIfEmpty { exploreFields["intro"] = v }
            if let v = e.exploreKind?.nilIfEmpty { exploreFields["kind"] = v }
            if let v = e.exploreLastChapter?.nilIfEmpty { exploreFields["lastChapter"] = v }
            if let v = e.exploreBookUrl?.nilIfEmpty { exploreFields["bookUrl"] = v }
            if let v = e.exploreCoverUrl?.nilIfEmpty { exploreFields["coverUrl"] = v }
            if let v = e.exploreWordCount?.nilIfEmpty { exploreFields["wordCount"] = v }
        }

        return BookSource(
            bookSourceName: name,
            bookSourceUrl: url,
            bookSourceGroup: group,
            bookSourceType: 0,
            enabled: true,
            weight: 100,
            searchUrl: raw.searchUrl,
            exploreUrl: raw.exploreUrl,
            ruleSearch: searchFields.isEmpty ? nil : SourceRule(fields: searchFields),
            ruleBookInfo: infoFields.isEmpty ? nil : SourceRule(fields: infoFields),
            ruleToc: tocFields.isEmpty ? nil : SourceRule(fields: tocFields),
            ruleContent: contentFields.isEmpty ? nil : SourceRule(fields: contentFields),
            ruleExplore: exploreFields.isEmpty ? nil : SourceRule(fields: exploreFields),
            header: raw.header,
            loginUrl: raw.loginUrl
        )
    }
}

// MARK: - HuaHuo Raw Codable Models

struct HuaHuoRawSource: Codable, Sendable {
    var sourceName: String?
    var name: String?
    var sourceUrl: String?
    var url: String?
    var sourceGroup: String?
    var searchUrl: String?
    var exploreUrl: String?
    var header: String?
    var loginUrl: String?
    var ruleExplore: HuaHuoRawExploreRule?
    var ruleSearch: HuaHuoRawSearchRule?
    var ruleBookInfo: HuaHuoRawBookInfoRule?
    var ruleToc: HuaHuoRawTocRule?
    var ruleContent: HuaHuoRawContentRule?
}

struct HuaHuoRawExploreRule: Codable, Sendable {
    var exploreBookList: String?
    var exploreName: String?
    var exploreAuthor: String?
    var exploreIntro: String?
    var exploreKind: String?
    var exploreLastChapter: String?
    var exploreBookUrl: String?
    var exploreCoverUrl: String?
    var exploreWordCount: String?
}

struct HuaHuoRawSearchRule: Codable, Sendable {
    var searchBookList: String?
    var searchName: String?
    var searchAuthor: String?
    var searchIntro: String?
    var searchKind: String?
    var searchLastChapter: String?
    var searchBookUrl: String?
    var searchCoverUrl: String?
    var searchWordCount: String?
}

struct HuaHuoRawBookInfoRule: Codable, Sendable {
    var infoName: String?
    var infoAuthor: String?
    var infoIntro: String?
    var infoKind: String?
    var infoLastChapter: String?
    var infoUpdateTime: String?
    var infoCoverUrl: String?
    var infoTocUrl: String?
    var infoWordCount: String?
}

struct HuaHuoRawTocRule: Codable, Sendable {
    var tocList: String?
    var tocName: String?
    var tocUrl: String?
    var isVip: String?
    var tocUpdateTime: String?
    var nextTocUrl: String?
}

struct HuaHuoRawContentRule: Codable, Sendable {
    var content: String?
    var nextContentUrl: String?
    var webJs: String?
    var sourceRegex: String?
    var replaceRegex: String?
}

