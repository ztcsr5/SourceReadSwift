import Foundation

/// Restricts imported preferences to the settings exported by the backup format.
enum AppBackupPreferences {
    static var keys: [String] {
        ["reader.fontSize", "reader.lineSpacing", "reader.pagePadding", "reader.letterSpacing",
         "reader.paragraphSpacing", "reader.paragraphIndent", "reader.titleSpacing", "reader.footerHeight",
         "reader.ttsRate", "reader.autoScrollDelay", "reader.sleepTimerMinutes", "reader.background",
         "reader.mode", "reader.tapZones", "reader.keepScreenAwake", "reader.preloadChapterCount",
         "reader.textSelectionEnabled", "settings.themeMode", "settings.visualTheme"]
        + AppVisualTheme.allCases.flatMap { [$0.preferenceKey("accent"), $0.preferenceKey("secondaryAccent")] }
    }

    static func validate(_ preferences: [String: BackupPreferenceValue]) throws {
        var appearance = ReaderBindingPreferences.defaults
        for (key, raw) in preferences where keys.contains(key) {
            let value = normalized(raw, for: key)
            if appearance[key] != nil {
                switch value {
                case .string(let text): appearance[key] = .text(text)
                case .double(let number): appearance[key] = .number(number)
                case .integer(let number): appearance[key] = .number(Double(number))
                case .bool(let flag): appearance[key] = .flag(flag)
                }
                continue
            }
            guard isValid(value, for: key) else { throw AppDataBackupError.invalidPreferences }
        }
        do { try ReaderBindingPreferences(values: appearance).validate() }
        catch { throw AppDataBackupError.invalidPreferences }
    }

    static func apply(_ preferences: [String: BackupPreferenceValue], to defaults: UserDefaults) throws {
        try validate(preferences)
        for (key, raw) in preferences where keys.contains(key) {
            let value = normalized(raw, for: key)
            switch value {
            case .string(let text): defaults.set(text, forKey: key)
            case .double(let number): defaults.set(number, forKey: key)
            case .integer(let number): defaults.set(number, forKey: key)
            case .bool(let flag): defaults.set(flag, forKey: key)
            }
        }
    }

    private static func normalized(_ value: BackupPreferenceValue, for key: String) -> BackupPreferenceValue {
        // Schema v2 stored every preference as text; retain that import path.
        guard case .string(let text) = value else { return value }
        if ["reader.sleepTimerMinutes", "reader.preloadChapterCount"].contains(key), let number = Int(text) {
            return .integer(number)
        }
        if ["reader.keepScreenAwake", "reader.textSelectionEnabled"].contains(key) {
            if ["true", "1"].contains(text.lowercased()) { return .bool(true) }
            if ["false", "0"].contains(text.lowercased()) { return .bool(false) }
        }
        if case .number? = ReaderBindingPreferences.defaults[key], let number = Double(text) { return .double(number) }
        if ["reader.ttsRate", "reader.autoScrollDelay"].contains(key), let number = Double(text) { return .double(number) }
        if key == "reader.mode", text == "paged" { return .string(ReaderMode.pageTurn.rawValue) }
        return value
    }

    private static func isValid(_ value: BackupPreferenceValue, for key: String) -> Bool {
        switch (key, value) {
        case ("reader.mode", .string(let text)): return ReaderMode(rawValue: text) != nil || text == "paged"
        case ("settings.themeMode", .string(let text)): return ["system", "light", "dark", "eyeCare"].contains(text)
        case ("settings.visualTheme", .string(let text)): return AppVisualTheme(rawValue: text) != nil
        case ("reader.tapZones", .string(let text)): return text.utf8.count <= 2048
        case ("reader.keepScreenAwake", .bool), ("reader.textSelectionEnabled", .bool): return true
        case ("reader.ttsRate", .double(let number)): return number.isFinite && (0...1).contains(number)
        case ("reader.autoScrollDelay", .double(let number)):
            return number.isFinite && (ReaderAutomationPolicy.minDelay...ReaderAutomationPolicy.maxDelay).contains(number)
        case ("reader.sleepTimerMinutes", .integer(let number)): return (-1...1440).contains(number)
        case ("reader.preloadChapterCount", .integer(let number)):
            return (ReaderPreloadPolicy.minimumCount...ReaderPreloadPolicy.maximumCount).contains(number)
        case (_, .string(let text)) where key.hasSuffix("Hex"):
            return text.isEmpty || (text.count == 6 && text.allSatisfy(\.isHexDigit))
        default: return false
        }
    }
}
