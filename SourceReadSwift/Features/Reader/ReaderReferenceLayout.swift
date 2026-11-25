import SwiftUI

/// Reversible Qiyue ("栖阅") typography & chrome preset. Never snapshots the book, reading mode or paper.
enum ReaderReferenceLayout {
    static let activeKey = "reader.templateOneActive"
    private static let previousKey = "reader.templateOnePrevious"
    private static let settings: [String: Any] = [
        "reader.fontSize": 18.0, "reader.lineSpacing": 10.0, "reader.letterSpacing": 0.0,
        "reader.paragraphIndent": 36.0, "reader.paragraphSpacing": 10.0, "reader.pagePadding": 20.0,
        "reader.verticalPadding": 6.0, "reader.fontFamily": "system", "reader.fontWeight": "regular",
        "reader.textAlignment": "justified", "reader.chapterHeadingStyle": "header", "reader.chapterDecoration": "none",
        "reader.chapterTitleFamily": "", "reader.chapterTitleSize": 21.2, "reader.chapterTitleBold": true,
        "reader.titleSpacing": 28.0, "reader.chapterAlignment": "leading",
        "reader.headerFontSize": 11.5, "reader.headerOpacity": 0.52, "reader.headerTopGap": 4.0,
        "reader.headerLeftSlot": "chapterTitle", "reader.headerCenterSlot": "none", "reader.headerRightSlot": "none",
        "reader.footerHeight": 48.0,
        "reader.footerLeftSlot": "time", "reader.footerCenterSlot": "none", "reader.footerRightSlot": "pageAndBattery",
        "reader.statusPosition": "bottom", "reader.showSystemStatusBar": false, "reader.chromeShowDivider": false,
        "reader.footerShowTime": true, "reader.footerShowBatteryPercent": true, "reader.footerShowBatteryIcon": true,
        "reader.customInkHex": "222222", "reader.inkOpacity": 1.0
    ]

    static func apply(to defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: activeKey) else { return }
        defaults.set(settings.keys.reduce(into: [String: Any]()) { $0[$1] = defaults.object(forKey: $1) }, forKey: previousKey)
        for (key, value) in settings { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: activeKey)
    }

    static func restore(in defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: activeKey), let previous = defaults.dictionary(forKey: previousKey) else { return }
        for key in settings.keys {
            if let oldValue = previous[key] {
                defaults.set(oldValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.removeObject(forKey: previousKey)
        defaults.removeObject(forKey: activeKey)
    }
}

struct ReaderReferenceLayoutControl: View {
    @AppStorage(ReaderReferenceLayout.activeKey) private var isActive = false
    var body: some View {
        Toggle(isOn: Binding(get: { isActive }, set: { selected in
            if selected { ReaderReferenceLayout.apply() } else { ReaderReferenceLayout.restore() }
        })) { Label("栖阅模版", systemImage: "text.book.closed") }
        .accessibilityIdentifier("readerSettings.templateOne")
    }
}
