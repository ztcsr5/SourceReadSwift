import Foundation

/// Bounded typography shared by page measurement, rendering and the settings preview.
enum ReaderHeadingPreferences {
    static func titleSize(custom: Double, body: Double) -> Double {
        guard custom.isFinite, custom > 0 else { return ReaderTypographyDefaults.titleFontSize(for: body) }
        return min(max(custom, 14), 44)
    }
    static func headerSize(_ value: Double) -> Double { value.isFinite ? min(max(value, 9), 18) : 12 }
    static func headerGap(_ value: Double) -> Double { value.isFinite ? min(max(value, 0), 24) : 2 }
    static func opacity(_ value: Double) -> Double { value.isFinite ? min(max(value, 0.35), 1) : 0.82 }
    static func showsTopStatus(position: String, systemBar: Bool, allowsDuplicates: Bool) -> Bool {
        (position == "top" || position == "both") && (!systemBar || allowsDuplicates)
    }
}
