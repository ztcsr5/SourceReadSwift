import Foundation

struct PurifyRule: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var pattern: String
    var enabled: Bool

    init(id: String = UUID().uuidString, pattern: String, enabled: Bool = true) {
        self.id = id
        self.pattern = pattern
        self.enabled = enabled
    }
}

struct PurifyRulePreset: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var detail: String
    var patterns: [String]

    static let builtIn: [PurifyRulePreset] = [
        PurifyRulePreset(
            id: "ads",
            title: "广告与推广",
            detail: "删除常见章节内广告、推广、备用网址提示。",
            patterns: [
                "(?im)^\\s*(?:最新网址|备用网址|请记住本站域名)[：:][^\\r\\n]*(?:\\r?\\n|$)##",
                "(?im)^\\s*(?:请下载本站APP|请在APP内阅读|关注本站公众号)[^\\r\\n]*(?:\\r?\\n|$)##"
            ]
        ),
        PurifyRulePreset(
            id: "site-tail",
            title: "站点尾巴",
            detail: "删除站点在正文首尾追加的收藏、推荐、版权尾巴。",
            patterns: [
                "(?m)^\\s*请收藏本站[^\\r\\n]*(?:\\r?\\n|$)##",
                "(?m)^\\s*本章未完[，,。 ]*请点击下一页继续阅读[^\\r\\n]*(?:\\r?\\n|$)##",
                "(?m)^\\s*章节错误[，,。 ]*请点击报错[^\\r\\n]*(?:\\r?\\n|$)##"
            ]
        ),
        PurifyRulePreset(
            id: "noise",
            title: "乱码与占位",
            detail: "删除常见空白占位、重复分隔符和正文噪声。",
            patterns: [
                "[\\u200B\\uFEFF]##",
                "(?m)^[ \\t]*[-=]{8,}[ \\t]*$##"
            ]
        ),
        PurifyRulePreset(
            id: "navigation-lines",
            title: "独立导航行 · 保守",
            detail: "只删除整行的上一章、下一章、返回目录等按钮文字；不会删除句子或对话里的同名词。按需导入。",
            patterns: [
                "(?m)^[ \\t]*(?:上一章|下一章|返回目录|章节目录|加入书签|返回书架)[ \\t]*(?:\\r?\\n|$)##",
                "(?m)^[ \\t]*(?:上一页|下一页)[ \\t]*(?:\\r?\\n|$)##"
            ]
        ),
        PurifyRulePreset(
            id: "page-markers",
            title: "网页分页标记 · 可选",
            detail: "删除单独一行的“第1/3页”等网页分页标记；如原书有相同独立行，请勿启用。",
            patterns: [
                "(?m)^[ \\t]*[（(]?第[ \\t]*[0-9]+[ \\t]*/[ \\t]*[0-9]+[ \\t]*页[）)]?[ \\t]*(?:\\r?\\n|$)##"
            ]
        ),
        PurifyRulePreset(
            id: "site-link-prompts",
            title: "带网址的访问提示 · 保守",
            detail: "仅删除固定提示开头、后接完整 HTTP(S) 网址的独立行，保留正文中的网址与对话。",
            patterns: [
                "(?im)^[ \\t]*(?:手机用户请访问|本书最新章节请访问|请访问备用网址)[：: \\t]+https?://[^ \\t\\r\\n]+[ \\t]*(?:\\r?\\n|$)##"
            ]
        ),
        PurifyRulePreset(
            id: "control-residue",
            title: "不可见控制符与空白残留",
            detail: "移除非换行/制表的 ASCII 控制符，以及纯空白 HTML 占位行；不替换引号、繁简字或正常标点。",
            patterns: [
                "[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F]##",
                "(?im)^[ \\t]*(?:&nbsp;|&#160;|&#xA0;|<br[ \\t]*/?>)+[ \\t]*(?:\\r?\\n|$)##"
            ]
        ),
        PurifyRulePreset(
            id: "anti-scraping",
            title: "防盗与伪源水印",
            detail: "删除固定首发、发布与网址提示行；按需导入，先预览，避免误删作者原文。",
            patterns: [
                "(?im)^[ \\t]*(?:请记住本书首发域名[：:]|本文由[^\\r\\n]*整理发布|(?:笔趣阁|69书吧|飘天文学(?:网)?)[^\\r\\n]*首发[：: \\t]|最新网址[：:])[^\\r\\n]*(?:\\r?\\n|$)##",
                "(?im)^\\s*(?:天才一秒记住|顶点小说.*提供|小说网.*更新最快|本章未完，请点击下一页)[^\\r\\n]*(?:\\r?\\n|$)##"
            ]
        ),
        PurifyRulePreset(
            id: "social-groups",
            title: "读者群与社交引流",
            detail: "清理官方QQ群、书友交流群、加群看无删减、微信公众号等引流信息。",
            patterns: [
                "(?im)^\\s*(?:官方QQ群|读者群|书友交流群|加群看无删减|关注微信公众号|微信公众号)[：:][^\\r\\n]*(?:\\r?\\n|$)##",
                "(?im)^\\s*(?:QQ群号|扣扣群|企鹅群)[：:\\s]*[0-9]{5,12}[^\\r\\n]*(?:\\r?\\n|$)##"
            ]
        ),
        PurifyRulePreset(
            id: "author-notes",
            title: "作者附言与求票 · 可选",
            detail: "会删除任意位置以 PS、作者有话说或求票开头的整行，包括作者原文；只在确定不需要附言时导入。",
            patterns: [
                "(?im)^\\s*(?:求月票|求推荐票|求打赏|求订阅|求全订|投推荐票|投月票|感谢各位书友的打赏)[^\\r\\n]*(?:\\r?\\n|$)##",
                "(?im)^\\s*(?:PS[:：]|作者有话说[:：]|PS：今日已更新)[^\\r\\n]*(?:\\r?\\n|$)##"
            ]
        ),
        PurifyRulePreset(
            id: "transcode-alerts",
            title: "转码与缺字提示",
            detail: "清理“本章字数过少、如遇断更请退出转码、内容手打中”等抓取残留提示。",
            patterns: [
                "(?im)^\\s*(?:本章内容字数过少|如遇断更|请退出转码页面|如果章节有错误|点击刷新重新加载)[^\\r\\n]*(?:\\r?\\n|$)##",
                "(?im)^\\s*(?:内容防盗防乱抓|内容正在手打中|章节内容更新中)[^\\r\\n]*(?:\\r?\\n|$)##"
            ]
        )
    ]
}

@MainActor
final class PurifyRuleStore: ObservableObject {
    @Published private(set) var rules: [PurifyRule] = []
    @Published private(set) var lastError: String?
    @Published private(set) var validationErrors: [String: String] = [:]

    private let persistence: PurifyRulePersistence

    init(persistence: PurifyRulePersistence = PurifyRulePersistence()) {
        self.persistence = persistence
        do {
            rules = try persistence.load()
            updateValidationErrors()
        } catch {
            lastError = error.localizedDescription
        }
    }

    var enabledPatterns: [String] {
        rules
            .filter { $0.enabled && validationErrors[$0.id] == nil }
            .map(\.pattern)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    @discardableResult
    func add(_ pattern: String) -> Bool {
        let clean = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if let failure = PurifyRuleValidator.error(in: clean) {
            lastError = failure
            return false
        }
        guard !containsPattern(clean) else { lastError = nil; return true }
        return persist([PurifyRule(pattern: clean)] + rules)
    }

    func importLines(_ text: String) -> Int {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let values = clean.hasPrefix("@js:") || clean.hasPrefix("<js>")
            ? [clean] : text.components(separatedBy: CharacterSet.newlines)
        return importPatterns(values)
    }

    @discardableResult
    func importPatterns(_ patterns: [String]) -> Int {
        var seen = Set(rules.map(\.pattern))
        let values = patterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
        for (offset, value) in values.enumerated() {
            if let failure = PurifyRuleValidator.error(in: value) {
                lastError = "第 \(offset + 1) 条待导入规则：\(failure)。本次未导入，请修改后重试。"
                return 0
            }
        }
        guard !values.isEmpty else { lastError = nil; return 0 }
        return persist(values.map { PurifyRule(pattern: $0) } + rules) ? values.count : 0
    }

    func containsPattern(_ pattern: String) -> Bool {
        let clean = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        return rules.contains { $0.pattern == clean }
    }

    func setEnabled(_ enabled: Bool, ruleID: String) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        if enabled, let failure = PurifyRuleValidator.error(in: rules[index].pattern) {
            lastError = failure
            return
        }
        var updated = rules
        updated[index].enabled = enabled
        persist(updated)
    }

    func setAllEnabled(_ enabled: Bool) {
        guard rules.contains(where: { $0.enabled != enabled }) else { return }
        if enabled, let invalid = rules.first(where: { PurifyRuleValidator.error(in: $0.pattern) != nil }) {
            lastError = PurifyRuleValidator.error(in: invalid.pattern)
            return
        }
        let updated = rules.map { rule in
            var updated = rule
            updated.enabled = enabled
            return updated
        }
        persist(updated)
    }

    func preview(text: String) -> String {
        PurifyRuleEvaluator.apply(rules: enabledPatterns, to: text)
    }

    func backupSnapshot() -> [PurifyRule] { rules }

    @discardableResult
    func restore(_ snapshot: [PurifyRule]) -> Bool {
        let normalized = snapshot.filter { !$0.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return persist(normalized)
    }

    func remove(ruleID: String) {
        persist(rules.filter { $0.id != ruleID })
    }

    @discardableResult
    private func persist(_ updated: [PurifyRule]) -> Bool {
        do {
            try persistence.save(updated)
            rules = updated
            updateValidationErrors()
            lastError = nil
            return true
        } catch {
            lastError = "保存净化规则失败，原规则未改变：\(error.localizedDescription)"
            return false
        }
    }

    private func updateValidationErrors() {
        validationErrors = rules.reduce(into: [:]) { errors, rule in
            errors[rule.id] = PurifyRuleValidator.error(in: rule.pattern)
        }
    }
}

struct PurifyRulePersistence {
    private let fileManager: FileManager
    private let fileName = "purify_rules.json"
    private let rootURL: URL?

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL
    }

    func load() throws -> [PurifyRule] {
        let url = try storageURL()
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([PurifyRule].self, from: data)
    }

    func save(_ rules: [PurifyRule]) throws {
        let url = try storageURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(rules)
        try data.write(to: url, options: [.atomic])
    }

    private func storageURL() throws -> URL {
        if let rootURL {
            return rootURL.appendingPathComponent(fileName)
        }
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("SourceReadSwift", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
