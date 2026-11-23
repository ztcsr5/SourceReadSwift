import SwiftUI

/// A reversible typography preset. It never snapshots the book, reading mode or paper.
enum ReaderReferenceLayout {
    static let activeKey = "reader.templateOneActive"
    private static let previousKey = "reader.templateOnePrevious"
    private static let settings: [String: Any] = [
        "reader.fontSize": 18.0, "reader.lineSpacing": 10.0, "reader.letterSpacing": 0.0,
        "reader.paragraphIndent": 36.0, "reader.paragraphSpacing": 10.0, "reader.pagePadding": 20.0,
        "reader.verticalPadding": 4.0, "reader.fontFamily": "system", "reader.fontWeight": "regular",
        "reader.textAlignment": "justified", "reader.chapterHeadingStyle": "header", "reader.chapterDecoration": "none",
        "reader.chapterTitleFamily": "", "reader.chapterTitleSize": 21.0, "reader.chapterTitleBold": true,
        "reader.titleSpacing": 28.0, "reader.chapterAlignment": "leading",
        "reader.headerFontSize": 11.0, "reader.headerOpacity": 0.58, "reader.headerTopGap": 4.0,
        "reader.headerLeftSlot": "chapterTitle", "reader.headerCenterSlot": "none", "reader.headerRightSlot": "none",
        "reader.footerLeftSlot": "pageAndPercent", "reader.footerCenterSlot": "none", "reader.footerRightSlot": "timeAndBattery",
        "reader.statusPosition": "bottom", "reader.showSystemStatusBar": true, "reader.chromeShowDivider": false,
        "reader.footerShowTime": true, "reader.footerShowBatteryPercent": true, "reader.footerShowBatteryIcon": true
    ]

    static func apply(to defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: activeKey) else { return }
        defaults.set(settings.keys.reduce(into: [String: Any]()) { $0[$1] = defaults.object(forKey: $1) }, forKey: previousKey)
        for (key, value) in settings { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: activeKey)
    }

    static func restore(in defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: activeKey), let previous = defaults.dictionary(forKey: previousKey) else { return }
        for key in settings.keys { defaults.set(previous[key], forKey: key) }
        defaults.removeObject(forKey: previousKey)
        defaults.removeObject(forKey: activeKey)
    }
}

struct ReaderReferenceLayoutControl: View {
    @AppStorage(ReaderReferenceLayout.activeKey) private var isActive = false
    var body: some View {
        Toggle(isOn: Binding(get: { isActive }, set: { selected in
            if selected { ReaderReferenceLayout.apply() } else { ReaderReferenceLayout.restore() }
        })) { Label("模版1", systemImage: "text.book.closed") }
        .accessibilityIdentifier("readerSettings.templateOne")
    }
}
