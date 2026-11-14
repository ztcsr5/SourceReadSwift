import SwiftUI
import UIKit

enum AppVisualTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    // 4 Core Whitelisted Themes
    case forest
    case classic
    case kleinSage
    case inkwash
    // 4 Bespoke Atmospheric Theme Packs
    case shuimo
    case wuxia
    case anime
    case kawaii
    // Custom Theme Workshop
    case custom

    var id: String { rawValue }

    static let selectionKey = "settings.visualTheme"
    static let initialSelection: Self = .forest
    static let legacyFallback: Self = .classic

    static let whitelistedCoreThemes: [Self] = [.forest, .classic, .kleinSage, .inkwash]
    static let atmosphericThemes: [Self] = [.shuimo, .wuxia, .anime, .kawaii]

    static let classicDeskThemes: [Self] = [.classic, .kleinSage, .anime, .kawaii, .custom]
    static let floatingBookThemes: [Self] = [.forest, .inkwash, .shuimo, .wuxia]
    static let videoGlassThemes: [Self] = []

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = Self.migrated(from: raw)
    }

    static func migrated(from rawValue: String) -> Self {
        if let exact = Self(rawValue: rawValue) {
            return exact
        }
        return .legacyFallback
    }

    var usesFloatingBook: Bool { Self.floatingBookThemes.contains(self) }

    enum HomeComposition: String, CaseIterable, Identifiable, Hashable, Sendable {
        case readingDesk
        case editorial
        case index
        case gallery

        var id: String { rawValue }

        var title: String {
            switch self {
            case .readingDesk: return "书台 · 经典阅读卡"
            case .editorial: return "书刊 · 分栏排版卡"
            case .index: return "索引 · 紧凑目录"
            case .gallery: return "封面墙 · 双列陈列"
            }
        }

        var subtitle: String {
            switch self {
            case .readingDesk: return "凸显主读书籍与书台立体质感"
            case .editorial: return "杂志式留白分栏与章节边注"
            case .index: return "信息高密度横卡，书架快速浏览"
            case .gallery: return "双列大封面陈列，画册般浏览体验"
            }
        }
    }

    var homeComposition: HomeComposition {
        switch self {
        case .forest, .classic, .shuimo, .custom: return .readingDesk
        case .kleinSage, .wuxia: return .editorial
        case .inkwash: return .index
        case .anime, .kawaii: return .gallery
        }
    }

    func resolvedHomeComposition(in defaults: UserDefaults = .standard) -> HomeComposition {
        HomeCompositionPreference.selectedComposition(in: defaults) ?? homeComposition
    }

    var usesFramedShelf: Bool {
        usesFramedShelf(for: resolvedHomeComposition())
    }

    func usesFramedShelf(for composition: HomeComposition) -> Bool {
        composition == .gallery && !isAtelier && !usesNeutralGlass
    }

    var compositionTitle: String {
        switch resolvedHomeComposition() {
        case .readingDesk: return "书台 · 三列藏书"
        case .editorial: return "书刊 · 分栏阅读卡"
        case .index: return "索引 · 紧凑目录"
        case .gallery: return "封面墙 · 双列陈列"
        }
    }

    var illustratedPaper: ReaderBackground? {
        switch self {
        case .inkwash: return .mountains
        default: return nil
        }
    }

    func atmosphericPaperAsset(isDark: Bool) -> String? {
        switch self {
        case .shuimo: return isDark ? "ThemeShuimoNight" : "ThemeShuimoDay"
        case .wuxia: return isDark ? "ThemeWuxiaNight" : "ThemeWuxiaDay"
        case .anime: return isDark ? "ThemeAnimeNight" : "ThemeAnimeDay"
        case .kawaii: return isDark ? "ThemeKawaiiNight" : "ThemeKawaiiDay"
        default: return nil
        }
    }

    static var current: Self { selected(in: .standard) }

    static func selected(in defaults: UserDefaults) -> Self {
        guard let raw = defaults.string(forKey: selectionKey), !raw.isEmpty else {
            return initialSelection
        }
        return migrated(from: raw)
    }

    static func bootstrapSelection(in defaults: UserDefaults) {
        if let raw = defaults.string(forKey: selectionKey), !raw.isEmpty {
            if Self(rawValue: raw) == nil {
                defaults.set(legacyFallback.rawValue, forKey: selectionKey)
            }
            return
        }
        let wasClassic = defaults.bool(forKey: BookshelfStore.welcomeSeedPreferenceKey)
            || ["accent", "secondaryAccent"].contains { defaults.object(forKey: Self.classic.preferenceKey($0)) != nil }
        defaults.set(wasClassic ? Self.classic.rawValue : initialSelection.rawValue, forKey: selectionKey)
    }

    var title: String {
        switch self {
        case .forest: return "森林绿"
        case .classic: return "纸间 · 原初（白紫）"
        case .kleinSage: return "蓝艾 · 海报书刊"
        case .inkwash: return "水墨留白"
        case .shuimo: return "水墨丹青"
        case .wuxia: return "江湖武侠"
        case .anime: return "晴空二次元"
        case .kawaii: return "可爱手账"
        case .custom: return "自定义主题工坊"
        }
    }

    var detail: String {
        switch self {
        case .forest: return "通体纯白极简无框 · 清透玻璃 · 夜间深灰统一"
        case .classic: return "原有白紫经典搭配 · 柔和圆角 · 轻透卡片"
        case .kleinSage: return "克莱因蓝 × 艾绿 · 清晰分栏 · 极夜深蓝护目"
        case .inkwash: return "山水留白 · 宣纸微影 · 极简墨线排布"
        case .shuimo: return "宣纸山水底纹 × 书法题铭 · 朱砂印点缀 · 松烟夜读"
        case .wuxia: return "竹林夜雨古卷 × 剑青玄铁赤金 · 侠气题跋质感"
        case .anime: return "晴空樱瓣浅彩 × 夜间柔和霓虹散景 · 清透圆角"
        case .kawaii: return "奶油草莓抹茶手账底纹 · 轻盈静态胶带 · 圆体字形"
        case .custom:
            let preset = AppCustomThemeStore.currentPreset
            return "\(preset.name) · \(preset.backdropKind.title) · 支持相册选图与一键配色"
        }
    }

    var accentHex: UInt32 {
        switch self {
        case .forest: return 0x3D6348
        case .classic: return 0x594FDB
        case .kleinSage: return 0x012696
        case .inkwash: return 0x2F3B36
        case .shuimo: return 0x242A2C
        case .wuxia: return 0x165347
        case .anime: return 0xB82E5D
        case .kawaii: return 0xBA3759
        case .custom: return AppCustomThemeStore.currentPreset.lightAccentHex
        }
    }

    var secondaryHex: UInt32 {
        switch self {
        case .forest: return 0x526458
        case .classic: return 0x419BDC
        case .kleinSage: return 0x855A0C
        case .inkwash: return 0x6B7470
        case .shuimo: return 0xC23B29
        case .wuxia: return 0x8F631E
        case .anime: return 0x266BC7
        case .kawaii: return 0x3D6E47
        case .custom: return AppCustomThemeStore.currentPreset.lightSecondaryHex
        }
    }

    var darkAccentHex: UInt32 {
        switch self {
        case .forest: return 0xBAD6C0
        case .classic: return 0xB8B3FF
        case .kleinSage: return 0x9DB4FF
        case .inkwash: return 0xC8D3CD
        case .shuimo: return 0xD8E0DC
        case .wuxia: return 0x7ADBC9
        case .anime: return 0xFF93B8
        case .kawaii: return 0xFFA2BA
        case .custom: return AppCustomThemeStore.currentPreset.darkAccentHex
        }
    }

    var darkSecondaryHex: UInt32 {
        switch self {
        case .forest: return 0xAEBBB2
        case .classic: return 0x76C4FF
        case .kleinSage: return 0xFFD97A
        case .inkwash: return 0x9AA6A0
        case .shuimo: return 0xFF7D6B
        case .wuxia: return 0xE6C275
        case .anime: return 0x7ED8FF
        case .kawaii: return 0x9CD4A5
        case .custom: return AppCustomThemeStore.currentPreset.darkSecondaryHex
        }
    }

    var backgroundHex: UInt32 {
        switch self {
        case .forest: return 0xFFFFFF
        case .classic: return 0xF2F2F7
        case .kleinSage: return 0xF0F5F7
        case .inkwash: return 0xF7F6F1
        case .shuimo: return 0xF5EFE3
        case .wuxia: return 0xECF1EE
        case .anime: return 0xF5F8FF
        case .kawaii: return 0xFFF6F0
        case .custom: return AppCustomThemeStore.currentPreset.lightBackgroundHex
        }
    }

    var cardHex: UInt32 {
        switch self {
        case .forest: return 0xFFFFFF
        case .classic: return 0xFFFFFF
        case .kleinSage: return 0xFAFFFC
        case .inkwash: return 0xFCFAF4
        case .shuimo: return 0xFAF6EC
        case .wuxia: return 0xF6FAF8
        case .anime: return 0xFFFFFF
        case .kawaii: return 0xFFFFFF
        case .custom: return AppCustomThemeStore.currentPreset.lightCardHex
        }
    }

    var darkBackgroundHex: UInt32 {
        switch self {
        case .forest: return 0x151716
        case .classic: return 0x000000
        case .kleinSage: return 0x0A1231
        case .inkwash: return 0x101312
        case .shuimo: return 0x121617
        case .wuxia: return 0x0C1317
        case .anime: return 0x101425
        case .kawaii: return 0x20181C
        case .custom: return AppCustomThemeStore.currentPreset.darkBackgroundHex
        }
    }

    var darkCardHex: UInt32 {
        switch self {
        case .forest: return 0x222423
        case .classic: return 0x1C1C1E
        case .kleinSage: return 0x172344
        case .inkwash: return 0x1B1F1E
        case .shuimo: return 0x1C2224
        case .wuxia: return 0x152026
        case .anime: return 0x1B223C
        case .kawaii: return 0x2C2127
        case .custom: return AppCustomThemeStore.currentPreset.darkCardHex
        }
    }

    var radius: CGFloat {
        switch self {
        case .forest: return 22
        case .classic: return 18
        case .kleinSage: return 8
        case .inkwash: return 12
        case .shuimo: return 10
        case .wuxia: return 6
        case .anime: return 24
        case .kawaii: return 20
        case .custom: return CGFloat(AppCustomThemeStore.currentPreset.cornerRadius)
        }
    }

    var usesNeutralGlass: Bool { self == .forest }

    var supportsLiveGlass: Bool {
        switch self {
        case .inkwash: return false
        case .custom: return AppCustomThemeStore.currentPreset.cardSurface == .glass
        default: return true
        }
    }

    var isVideoGlass: Bool { false }

    func surfaceRadius(preferred: CGFloat?) -> CGFloat {
        guard let preferred else { return radius }
        if preferred >= 44 { return preferred }
        return radius
    }

    var primaryInk: Color { usesNeutralGlass ? dynamicColor(light: 0x1C211D, dark: 0xF0F2EF) : .primary }
    var secondaryInk: Color { usesNeutralGlass ? dynamicColor(light: 0x626862, dark: 0xABB1AB) : .secondary }
    var selectionSurfaceHex: UInt32 { 0xF3F3F0 }
    var neutralBorderHex: UInt32 { 0xE6E8E3 }
    var controlFill: Color { dynamicColor(light: selectionSurfaceHex, dark: 0x303430) }
    var controlBorder: Color { dynamicColor(light: neutralBorderHex, dark: 0x414641) }

    var borderWidth: CGFloat {
        switch self {
        case .forest: return 0
        case .wuxia, .kleinSage: return 0.9
        default: return 0.6
        }
    }

    var fontDesign: Font.Design {
        switch self {
        case .anime, .kawaii: return .rounded
        case .inkwash, .shuimo, .wuxia: return .serif
        case .custom: return AppCustomThemeStore.currentPreset.fontStyle.fontDesign
        default: return .default
        }
    }

    var displayFontName: String? {
        switch self {
        case .shuimo: return "MaShanZheng-Regular"
        case .wuxia: return "ZhiMangXing-Regular"
        case .custom: return AppCustomThemeStore.currentPreset.fontStyle.displayFontName
        default: return nil
        }
    }

    func titleFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        if let name = displayFontName {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight, design: fontDesign)
    }

    var ornament: String {
        switch self {
        case .forest: return "leaf"
        case .classic: return "book.closed"
        case .kleinSage: return "square.split.2x2"
        case .inkwash: return "mountain.2"
        case .shuimo: return "seal"
        case .wuxia: return "scroll"
        case .anime: return "sparkles"
        case .kawaii: return "heart"
        case .custom: return "slider.horizontal.3"
        }
    }

    func preferenceKey(_ component: String) -> String {
        self == .classic ? "settings.\(component)Hex" : "settings.visualTheme.\(rawValue).\(component)Hex"
    }

    func dynamicColor(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? Self.uiColor(dark) : Self.uiColor(light) })
    }

    static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

enum HomeCompositionPreference {
    static let storageKey = "settings.homeComposition"
    static let autoRawValue = "auto"

    static func selectedComposition(in defaults: UserDefaults = .standard) -> AppVisualTheme.HomeComposition? {
        guard let raw = defaults.string(forKey: storageKey),
              raw != autoRawValue else { return nil }
        return AppVisualTheme.HomeComposition(rawValue: raw)
    }
}

struct PaperBetweenMark: View {
    var size: CGFloat = 44
    @AppStorage(AppIconOption.storageKey) private var selectedIconRaw = AppIconOption.forest.rawValue

    var body: some View {
        let asset = AppIconOption.resolved(rawValue: selectedIconRaw).brandMarkAssetName
        Image(asset)
            .resizable().interpolation(.high).scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .stroke(.primary.opacity(0.08), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
            .accessibilityHidden(true)
    }
}
