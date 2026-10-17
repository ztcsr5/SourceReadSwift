import Foundation

/// Adapter for HuaHuo (花火阅读) book source format.
/// Automatically detects and normalizes HuaHuo's specialized rule fields
/// (e.g., `exploreBookList`, `searchCoverUrl`, `infoTocUrl`, `nextContentUrl`)
/// into standard Legado `BookSource` models.
public struct HuaHuoBookSourceAdapter: Sendable {

    // MARK: - Format Detection

    public static func isHuaHuoJSON(_ text: String) -> Bool {
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

    public static func isHuaHuoData(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return isHuaHuoJSON(text)
    }

    // MARK: - Import & Conversion

    public static func importSources(from text: String) -> [BookSource] {
        guard let data = text.data(using: .utf8) else { return [] }
        return importSources(from: data)
    }

    public static func importSources(from data: Data) -> [BookSource] {
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

    public static func adapt(raw: HuaHuoRawSource) -> BookSource? {
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

public struct HuaHuoRawSource: Codable, Sendable {
    public var sourceName: String?
    public var name: String?
    public var sourceUrl: String?
    public var url: String?
    public var sourceGroup: String?
    public var searchUrl: String?
    public var exploreUrl: String?
    public var header: String?
    public var loginUrl: String?
    public var ruleExplore: HuaHuoRawExploreRule?
    public var ruleSearch: HuaHuoRawSearchRule?
    public var ruleBookInfo: HuaHuoRawBookInfoRule?
    public var ruleToc: HuaHuoRawTocRule?
    public var ruleContent: HuaHuoRawContentRule?
}

public struct HuaHuoRawExploreRule: Codable, Sendable {
    public var exploreBookList: String?
    public var exploreName: String?
    public var exploreAuthor: String?
    public var exploreIntro: String?
    public var exploreKind: String?
    public var exploreLastChapter: String?
    public var exploreBookUrl: String?
    public var exploreCoverUrl: String?
    public var exploreWordCount: String?
}

public struct HuaHuoRawSearchRule: Codable, Sendable {
    public var searchBookList: String?
    public var searchName: String?
    public var searchAuthor: String?
    public var searchIntro: String?
    public var searchKind: String?
    public var searchLastChapter: String?
    public var searchBookUrl: String?
    public var searchCoverUrl: String?
    public var searchWordCount: String?
}

public struct HuaHuoRawBookInfoRule: Codable, Sendable {
    public var infoName: String?
    public var infoAuthor: String?
    public var infoIntro: String?
    public var infoKind: String?
    public var infoLastChapter: String?
    public var infoUpdateTime: String?
    public var infoCoverUrl: String?
    public var infoTocUrl: String?
    public var infoWordCount: String?
}

public struct HuaHuoRawTocRule: Codable, Sendable {
    public var tocList: String?
    public var tocName: String?
    public var tocUrl: String?
    public var isVip: String?
    public var tocUpdateTime: String?
    public var nextTocUrl: String?
}

public struct HuaHuoRawContentRule: Codable, Sendable {
    public var content: String?
    public var nextContentUrl: String?
    public var webJs: String?
    public var sourceRegex: String?
    public var replaceRegex: String?
}
