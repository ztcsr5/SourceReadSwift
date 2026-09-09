import Foundation
import SwiftUI
import UIKit

enum ReaderBackground: String, CaseIterable, Identifiable, Sendable {
    case paper      // 羊皮纸暖黄 (#EBD9BB)
    case kraft      // 复古牛皮 (#DDC090)
    case green      // 豆沙青绿 (#C2D8AA)
    case lavender   // 淡雅黛紫 (#DBB8E2)
    case azure      // 晴空天蓝 (#ABCEE0)
    case white      // 纯净素白 (#FFFFFF)
    case gray       // 浅灰银质 (#F2F2F7)
    case dark       // 极夜纯黑 (#000000)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: return "羊皮纸"
        case .kraft: return "牛皮纸"
        case .green: return "豆沙绿"
        case .lavender: return "黛紫"
        case .azure: return "青空"
        case .white: return "素白"
        case .gray: return "浅灰"
        case .dark: return "极黑"
        }
    }

    var color: Color {
        color(isNight: false)
    }

    var textColor: Color {
        textColor(isNight: false)
    }

    var uiTextColor: UIColor {
        uiTextColor(isNight: false)
    }

    func color(isNight: Bool) -> Color {
        Color(hex: isNight ? nightBackgroundHex : dayBackgroundHex)
    }

    func textColor(isNight: Bool) -> Color {
        Color(hex: isNight ? nightTextHex : dayTextHex)
    }

    func uiColor(isNight: Bool) -> UIColor {
        UIColor(hex: isNight ? nightBackgroundHex : dayBackgroundHex)
    }

    func uiTextColor(isNight: Bool) -> UIColor {
        UIColor(hex: isNight ? nightTextHex : dayTextHex)
    }

    var dayBackgroundHex: UInt32 {
        switch self {
        case .paper: return 0xEBD9BB
        case .kraft: return 0xDDC090
        case .green: return 0xC2D8AA
        case .lavender: return 0xDBB8E2
        case .azure: return 0xABCEE0
        case .white: return 0xFFFFFF
        case .gray: return 0xF2F2F7
        case .dark: return 0x000000
        }
    }

    var dayTextHex: UInt32 {
        switch self {
        case .paper: return 0x63543C
        case .kraft: return 0x3E3422
        case .green: return 0x596C44
        case .lavender: return 0x68516C
        case .azure: return 0x3D4C54
        case .white: return 0x000000
        case .gray: return 0x1C1C1E
        case .dark: return 0xFFFFFF
        }
    }

    var nightBackgroundHex: UInt32 {
        switch self {
        case .paper: return 0x1E2021
        case .kraft, .green, .lavender, .azure: return 0x3C3F43
        case .white: return 0x18181A
        case .gray: return 0x2C2C2E
        case .dark: return 0x000000
        }
    }

    var nightTextHex: UInt32 {
        switch self {
        case .paper, .kraft: return 0xDCDFE1
        case .green: return 0x88C16F
        case .lavender: return 0xF6AEAE
        case .azure: return 0x90BFF5
        case .white: return 0xE0E0E0
        case .gray: return 0xF2F2F7
        case .dark: return 0xFFFFFF
        }
    }

    func darkStatusIcon(isNight: Bool) -> Bool {
        if isNight { return false }
        switch self {
        case .paper, .kraft, .white, .gray: return true
        case .green, .lavender, .azure, .dark: return false
        }
    }
}

fileprivate extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xff) / 255.0
        let green = Double((hex >> 8) & 0xff) / 255.0
        let blue = Double(hex & 0xff) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

fileprivate extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let red = CGFloat((hex >> 16) & 0xff) / 255.0
        let green = CGFloat((hex >> 8) & 0xff) / 255.0
        let blue = CGFloat(hex & 0xff) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

enum ReaderMode: String, CaseIterable, Identifiable, Sendable {
    case scroll
    case pageTurn
    case cover

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scroll: return "滑动"
        case .pageTurn: return "平移"
        case .cover: return "覆盖"
        }
    }
}

enum ReaderFontFamily: String, CaseIterable, Identifiable, Sendable {
    case system
    case songti
    case kaiti
    case rounded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "系统默认"
        case .songti: return "思源宋体"
        case .kaiti: return "楷体"
        case .rounded: return "圆体"
        }
    }

    func uiFont(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        switch self {
        case .system:
            return UIFont.systemFont(ofSize: size, weight: weight)
        case .songti:
            let songtiNames = weight == .bold
                ? ["STSongti-SC-Bold", "Songti SC Bold", "SongtiSC-Bold", "STSong"]
                : ["STSongti-SC-Regular", "Songti SC", "SongtiSC-Regular", "STSong", "STSongti-SC-Light"]
            for name in songtiNames {
                if let font = UIFont(name: name, size: size) {
                    return font
                }
            }
            if let desc = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.serif) {
                return UIFont(descriptor: desc, size: size)
            }
            return UIFont.systemFont(ofSize: size, weight: weight)
        case .kaiti:
            let kaitiNames = weight == .bold
                ? ["STKaiti-SC-Bold", "Kaiti SC Bold", "KaitiSC-Bold", "STKaiti", "KaiTi"]
                : ["STKaiti-SC-Regular", "Kaiti SC", "KaitiSC-Regular", "STKaiti", "KaiTi"]
            for name in kaitiNames {
                if let font = UIFont(name: name, size: size) {
                    return font
                }
            }
            if let desc = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.serif) {
                return UIFont(descriptor: desc, size: size)
            }
            return UIFont.systemFont(ofSize: size, weight: weight)
        case .rounded:
            if let desc = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.rounded) {
                return UIFont(descriptor: desc, size: size)
            }
            return UIFont.systemFont(ofSize: size, weight: weight)
        }
    }
}

enum ReaderTypographyDefaults {
    static let fontSize: Double = 19
    static let lineSpacing: Double = 8
    static let letterSpacing: Double = 0
    static let paragraphSpacing: Double = 16
    static let paragraphIndent: Double = 38 // 2 characters * 19pt
    static let titleSpacing: Double = 20
    static let pagePadding: Double = 20
    static let footerHeight: Double = 72
}

enum ReaderTapAction: String, CaseIterable, Identifiable, Sendable {
    case previousPage
    case nextPage
    case previousChapter
    case nextChapter
    case menu
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .previousPage: return "上一页"
        case .nextPage: return "下一页"
        case .previousChapter: return "上一章"
        case .nextChapter: return "下一章"
        case .menu: return "菜单"
        case .disabled: return "无动作"
        }
    }

    var shortTitle: String {
        switch self {
        case .previousPage: return "上页"
        case .nextPage: return "下页"
        case .previousChapter: return "上章"
        case .nextChapter: return "下章"
        case .menu: return "菜单"
        case .disabled: return "关闭"
        }
    }

    var color: Color {
        switch self {
        case .previousPage, .previousChapter: return .blue
        case .nextPage, .nextChapter: return .green
        case .menu: return AppTheme.accent
        case .disabled: return .secondary
        }
    }

    static let defaultActions: [ReaderTapAction] = [
        .previousPage, .previousPage, .nextPage,
        .previousPage, .menu, .nextPage,
        .nextPage, .nextPage, .nextPage
    ]

    static var defaultRawValue: String {
        encode(defaultActions)
    }

    static func encode(_ actions: [ReaderTapAction]) -> String {
        actions.map(\.rawValue).joined(separator: ",")
    }

    static func decode(rawValue: String) -> [ReaderTapAction] {
        let values = rawValue
            .split(separator: ",")
            .map { ReaderTapAction(rawValue: String($0)) ?? .menu }
        guard values.count == 9 else { return defaultActions }
        return values.contains(.menu) ? values : defaultActions
    }
}

enum ReaderPreloadPolicy {
    static let defaultCount = 2
    static let minimumCount = 0
    static let maximumCount = 5

    static func clamp(_ count: Int) -> Int {
        min(max(count, minimumCount), maximumCount)
    }

    static func title(for count: Int) -> String {
        let value = clamp(count)
        return value == 0 ? "关闭" : "\(value) 章"
    }
}

/// Normalizes values entered beside reader sliders.  Keeping parsing and
/// clamping outside the view makes malformed persisted/input values harmless
/// and gives the XCTest target a deterministic contract for every setting.
enum ReaderValueNormalizer {
    static func clampedValue(
        from rawValue: String,
        range: ClosedRange<Double>
    ) -> Double? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        // A trailing decimal separator is a valid *draft* while the user is
        // typing, but it is not a committed value.  Treat it as invalid here
        // so blur/submit restores the last known-good value instead of
        // silently accepting a partial edit.
        guard !normalized.isEmpty,
              !normalized.hasSuffix("."),
              normalized != "+",
              normalized != "-",
              let parsed = Double(normalized),
              parsed.isFinite else {
            return nil
        }
        return min(max(parsed, range.lowerBound), range.upperBound)
    }

    static func formatted(_ value: Double, step: Double) -> String {
        guard value.isFinite else { return "0" }
        if step < 1 {
            return String(format: "%.2f", value)
                .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
        }
        return String(format: "%.0f", value)
    }
}

/// A compact numeric editor used next to every reader slider.  The draft text
/// is allowed to be temporarily incomplete (for example `1.` while typing),
/// then committed and clamped when editing ends or the keyboard submits.
struct ReaderNumberInput: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    @State private var draft: String
    @FocusState private var focused: Bool

    init(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String
    ) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
        _draft = State(initialValue: ReaderValueNormalizer.formatted(value.wrappedValue, step: step))
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: $draft, onEditingChanged: { isEditing in
                if !isEditing { commit() }
            }, onCommit: commit)
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .frame(width: 66)
            .focused($focused)
            .accessibilityLabel("输入\(title)")

            Text(unit)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 20, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .onChange(of: value) { updated in
            let formatted = ReaderValueNormalizer.formatted(updated, step: step)
            if draft != formatted, !focused {
                draft = formatted
            }
        }
    }

    private func commit() {
        guard let parsed = ReaderValueNormalizer.clampedValue(from: draft, range: range) else {
            draft = ReaderValueNormalizer.formatted(value, step: step)
            return
        }
        value = parsed
        draft = ReaderValueNormalizer.formatted(parsed, step: step)
    }
}
