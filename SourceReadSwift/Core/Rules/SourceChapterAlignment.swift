import Foundation

/// Source TOCs contain adverts, prefaces and different numbering conventions.
/// Never use the gateway's initial chapter once the live reader has advanced.
enum SourceChapterAlignment {
    static func match(title: String?, index: Int, in chapters: [BookChapter]) -> BookChapter? {
        guard !chapters.isEmpty else { return nil }
        let title = title ?? ""
        let normalized = key(title)
        if !normalized.isEmpty, let exact = chapters.first(where: { key($0.title) == normalized }) { return exact }
        if let number = number(title) {
            let numbered = chapters.filter { self.number($0.title) == number }
            if numbered.count == 1 { return numbered[0] }
            let suffix = body(title)
            if !suffix.isEmpty, let matched = numbered.first(where: { body($0.title) == suffix }) { return matched }
        }
        let suffix = body(title)
        let titled = suffix.isEmpty ? [] : chapters.filter { body($0.title) == suffix }
        if titled.count == 1 { return titled[0] }
        return chapters[min(max(0, index), chapters.count - 1)]
    }

    private static func key(_ s: String) -> String {
        let s = s.folding(options: [.widthInsensitive, .caseInsensitive], locale: Locale(identifier: "zh_Hans"))
        return String(s.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).contains($0) })
    }

    private static let prefix = try! NSRegularExpression(pattern: #"^\s*(?:第\s*)?([0-9０-９零〇一二两三四五六七八九十百千万]+)\s*[章回节集话]\s*"#)
    private static func body(_ s: String) -> String {
        key(prefix.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: ""))
    }
    static func number(_ s: String) -> Int? {
        let folded = s.folding(options: .widthInsensitive, locale: Locale(identifier: "zh_Hans"))
        guard let m = prefix.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded)),
              let range = Range(m.range(at: 1), in: folded) else { return nil }
        let digits = String(folded[range]); if let n = Int(digits) { return n }
        let values: [Character:Int] = ["零":0,"〇":0,"一":1,"二":2,"两":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9]
        let units: [Character:Int] = ["十":10,"百":100,"千":1000,"万":10000]
        if digits.allSatisfy({ values[$0] != nil }) {
            return Int(digits.compactMap { values[$0].map(String.init) }.joined())
        }
        var total = 0, section = 0, digit = 0
        for c in digits {
            if let n = values[c] { digit = n }
            else if let u = units[c] {
                if u == 10000 { section += digit; total += section * u; section = 0 }
                else { section += max(1, digit) * u }
                digit = 0
            }
        }
        return total + section + digit
    }
}
