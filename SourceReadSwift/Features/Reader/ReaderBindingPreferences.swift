import Foundation

/// Only reading appearance is captured: never progress, sources, accounts or playback.
enum ReaderBindingValue: Codable, Equatable, Sendable {
    case text(String), number(Double), flag(Bool)
    var propertyListValue: Any {
        switch self { case .text(let value): return value; case .number(let value): return value; case .flag(let value): return value }
    }
}

struct ReaderBindingPreferences: Codable, Equatable, Sendable {
    let values: [String: ReaderBindingValue]
    static let defaults: [String: ReaderBindingValue] = [
        "reader.fontFamily": .text(ReaderFontFamily.system.rawValue), "reader.customFontPostScriptName": .text(""),
        "reader.fontSize": .number(20), "reader.lineSpacing": .number(ReaderTypographyDefaults.lineSpacing),
        "reader.letterSpacing": .number(0), "reader.paragraphSpacing": .number(ReaderTypographyDefaults.paragraphSpacing),
        "reader.paragraphIndent": .number(40), "reader.pagePadding": .number(21),
        "reader.titleSpacing": .number(ReaderTypographyDefaults.titleSpacing), "reader.chapterTitleSize": .number(0),
        "reader.chapterTitleBold": .flag(true), "reader.chapterTitleFamily": .text(""),
        "reader.chapterDecoration": .text("none"), "reader.chapterAlignment": .text("leading"),
        "reader.chapterHeadingStyle": .text(ReaderPageChromeLayout.header.rawValue),
        "reader.headerFontSize": .number(12), "reader.headerTopGap": .number(2), "reader.headerOpacity": .number(0.82),
        "reader.footerHeight": .number(ReaderTypographyDefaults.footerHeight), "reader.footerShowTime": .flag(true),
        "reader.footerShowBatteryIcon": .flag(true), "reader.footerShowBatteryPercent": .flag(true),
        "reader.showSystemStatusBar": .flag(false), "reader.statusPosition": .text("bottom"),
        "reader.allowsDuplicateTopStatus": .flag(false), "reader.contentExtendsIntoChrome": .flag(false),
        "reader.background": .text(ReaderBackground.white.rawValue), "reader.customBackgroundIsDark": .flag(false),
        "reader.customWallpaperFillMode": .text(ReaderWallpaperFillMode.fill.rawValue),
        "reader.menuSurfaceStyle": .text("system"), "reader.menuPaperOpacity": .number(0.97), "reader.menuUsesWallpaper": .flag(false)
    ]
    private static let ranges: [String: ClosedRange<Double>] = [
        "reader.fontSize": 12...60, "reader.lineSpacing": 0...40, "reader.letterSpacing": 0...10,
        "reader.paragraphSpacing": 0...60, "reader.paragraphIndent": 0...100, "reader.pagePadding": 0...100,
        "reader.titleSpacing": 0...100, "reader.chapterTitleSize": 0...60, "reader.headerFontSize": 9...18,
        "reader.headerTopGap": 0...24, "reader.headerOpacity": 0.35...1, "reader.footerHeight": 0...200,
        "reader.menuPaperOpacity": 0.85...1
    ]
    static func capture(_ defaults: UserDefaults) throws -> Self {
        var values = Self.defaults
        for (key, fallback) in Self.defaults {
            guard let object = defaults.object(forKey: key) else { continue }
            switch fallback {
            case .text: guard let value = object as? String else { throw invalid(key) }; values[key] = .text(value)
            case .number: guard let value = object as? NSNumber else { throw invalid(key) }; values[key] = .number(value.doubleValue)
            case .flag: guard let value = object as? NSNumber else { throw invalid(key) }; values[key] = .flag(value.boolValue)
            }
        }
        let result = Self(values: values); try result.validate(); return result
    }
    func validate() throws {
        guard Set(values.keys) == Set(Self.defaults.keys) else { throw Self.invalid("设置清单") }
        for (key, value) in values {
            switch (value, Self.defaults[key]) {
            case (.text(let text), .some(.text(_))):
                guard text.count <= 256 else { throw Self.invalid(key) }
            case (.number(let number), .some(.number(_))):
                guard number.isFinite, Self.ranges[key]?.contains(number) == true else { throw Self.invalid(key) }
            case (.flag(_), .some(.flag(_))): break
            default: throw Self.invalid(key)
            }
        }
        let choices: [String: [String]] = [
            "reader.fontFamily": ReaderFontFamily.allCases.map(\.rawValue),
            "reader.chapterTitleFamily": [""] + ReaderFontFamily.allCases.map(\.rawValue),
            "reader.chapterDecoration": ReaderChapterDecoration.allCases.map(\.rawValue),
            "reader.chapterAlignment": ReaderChapterAlignment.allCases.map(\.rawValue),
            "reader.chapterHeadingStyle": ReaderPageChromeLayout.allCases.map(\.rawValue),
            "reader.background": ReaderBackground.allCases.map(\.rawValue),
            "reader.customWallpaperFillMode": ReaderWallpaperFillMode.allCases.map(\.rawValue),
            "reader.statusPosition": ["top", "bottom", "both"],
            "reader.menuSurfaceStyle": ["system", "paper"]
        ]
        for (key, allowed) in choices {
            guard case .some(.text(let text)) = values[key], allowed.contains(text) else { throw Self.invalid(key) }
        }
    }
    func text(_ key: String) -> String {
        if case .some(.text(let text)) = values[key] { return text }; return ""
    }
    func apply(to defaults: UserDefaults) throws {
        try validate()
        for (key, value) in values { defaults.set(value.propertyListValue, forKey: key) }
    }
    private static func invalid(_ key: String) -> NSError {
        NSError(domain: "ReaderBinding", code: 1, userInfo: [NSLocalizedDescriptionKey: "装帧方案的\(key)无效，原设置未改变。"])
    }
}
