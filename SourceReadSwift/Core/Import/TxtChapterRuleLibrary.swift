import Foundation

/// 一条 TXT 目录（章节）识别规则。
///
/// 规则是纯数据：只描述「怎么认标题」和「是否启用、优先级多少」，
/// 不含任何界面状态，便于导出、备份与单元测试。
struct TxtChapterRule: Codable, Equatable, Identifiable, Sendable {
    /// 稳定标识。用户改名不影响它，用于在整库编辑时定位同一条规则。
    let id: UUID
    var name: String
    /// 逐行匹配的正则；命中即视为章节标题。
    var pattern: String
    var isEnabled: Bool
    /// 数值越大越先尝试。同优先级按 `id` 排序，保证结果可复现。
    var priority: Int
    /// 内置规则不允许删除，只能停用，避免用户误删后再也找不回来。
    var isBuiltIn: Bool

    init(id: UUID = UUID(), name: String, pattern: String,
         isEnabled: Bool = true, priority: Int = 0, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.isEnabled = isEnabled
        self.priority = priority
        self.isBuiltIn = isBuiltIn
    }

    /// 校验结果只给出一条人话原因，供设置界面就地显示。
    enum PatternProblem: Equatable {
        case empty
        case tooLong
        case invalidRegex(String)

        var message: String {
            switch self {
            case .empty: return "规则不能为空"
            case .tooLong: return "正则不得超过 500 个字符，避免逐行匹配时拖慢导入"
            case .invalidRegex(let reason): return "正则无效：\(reason)"
            }
        }
    }

    var patternProblem: PatternProblem? {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if trimmed.count > 500 { return .tooLong }
        do {
            _ = try NSRegularExpression(pattern: trimmed, options: [.caseInsensitive])
            return nil
        } catch {
            return .invalidRegex(error.localizedDescription)
        }
    }

    var isValid: Bool { patternProblem == nil }
}

/// 可开关、带优先级的规则集合。
///
/// 语义是「按优先级从高到低逐个尝试，第一个命中决定结果」。这与旧的
/// 单条 `.custom(regex)` 不同：那时只有一条规则，要么命中要么退回内置。
/// `classify` 返回 `nil` 表示整库未启用或无可用规则，调用方回退到内置判断。
struct TxtChapterRuleLibrary: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var rules: [TxtChapterRule]

    static let disabled = TxtChapterRuleLibrary(isEnabled: false, rules: [])
    static let defaultsKey = "settings.txtChapterRules"

    /// 生效顺序：优先级降序，同优先级保持稳定顺序。
    var orderedEnabledRules: [TxtChapterRule] {
        rules.filter { $0.isEnabled && $0.isValid }
             .sorted { lhs, rhs in
                 if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                 return lhs.id.uuidString < rhs.id.uuidString
             }
    }

    /// `nil` = 不参与判断（关闭或没有有效规则），`true/false` = 命中/未命中。
    /// 注意：一旦库启用且有规则，未命中也返回 `false`，不会静默退回内置规则，
    /// 否则「关掉某条规则」在界面上看起来毫无变化。
    func classify(_ line: String) -> Bool? {
        guard isEnabled else { return nil }
        let active = orderedEnabledRules
        guard !active.isEmpty else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        for rule in active {
            guard let regex = Self.compiled(rule.pattern) else { continue }
            if regex.firstMatch(in: line, options: [], range: range) != nil { return true }
        }
        return false
    }

    /// Compiling a regex per line would dominate import time on a 10 MB novel;
    /// this keeps one compiled instance per pattern. A class with a lock avoids
    /// mutable static state in a `Sendable` value type.
    private final class RegexCache: @unchecked Sendable {
        static let shared = RegexCache()
        private var storage: [String: NSRegularExpression] = [:]
        private let lock = NSLock()

        func regex(for pattern: String) -> NSRegularExpression? {
            lock.lock()
            defer { lock.unlock() }
            if let hit = storage[pattern] { return hit }
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return nil
            }
            storage[pattern] = regex
            return regex
        }
    }

    private static func compiled(_ pattern: String) -> NSRegularExpression? {
        RegexCache.shared.regex(for: pattern)
    }

    // MARK: - 持久化

    static func load(from defaults: UserDefaults = .standard) -> TxtChapterRuleLibrary {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(TxtChapterRuleLibrary.self, from: data) else {
            return .seeded
        }
        return decoded
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    /// 首次运行的内置规则。全部默认关闭，避免改变现有导入结果；
    /// 用户在外观/阅读设置里显式打开后才接管判断。
    static let seeded = TxtChapterRuleLibrary(isEnabled: false, rules: [
        TxtChapterRule(name: "中文章节（第X章/回/节）",
                       pattern: #"^第\s*[0-9零〇一二三四五六七八九十百千万两壹贰叁肆伍陆柒捌玖拾佰仟]+\s*[章节回卷部集篇话話].*$"#,
                       priority: 100, isBuiltIn: true),
        TxtChapterRule(name: "卷/部标题",
                       pattern: #"^第\s*[0-9零〇一二三四五六七八九十百千万两]+\s*[卷部].*$"#,
                       priority: 90, isBuiltIn: true),
        TxtChapterRule(name: "英文章节（Chapter/Section）",
                       pattern: #"^(?:Chapter|Section|Part|Episode|Book)\s+[0-9IVXLCivxlc]+.*$"#,
                       priority: 80, isBuiltIn: true),
        TxtChapterRule(name: "数字序号（1. / 001、）",
                       pattern: #"^[0-9]{1,5}[.、,，_—\-].+$"#,
                       priority: 60, isBuiltIn: true),
        TxtChapterRule(name: "中文序号（一、二、）",
                       pattern: #"^[零〇一二三四五六七八九十百千]{1,8}[、.，_—\-].+$"#,
                       priority: 50, isBuiltIn: true),
        TxtChapterRule(name: "括注标题（【第一章】/（一））",
                       pattern: #"^[【〔〖「『〈［\[(（].{1,30}[】〕〗」』〉］\])）].{0,30}$"#,
                       priority: 40, isBuiltIn: true),
        TxtChapterRule(name: "序章/楔子/番外/后记",
                       pattern: #"^(?:序章|楔子|前言|序言|引子|正文|终章|后记|尾声|番外|简介|文案).{0,40}$"#,
                       priority: 30, isBuiltIn: true)
    ])

    /// 导入时只关心「有没有被用户改动过」，据此决定是否把规则传给解析器。
    var affectsImport: Bool { isEnabled && !orderedEnabledRules.isEmpty }
}
