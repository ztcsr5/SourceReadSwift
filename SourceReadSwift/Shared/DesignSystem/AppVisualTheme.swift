import SwiftUI
import UIKit

enum AppVisualTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    // Core whitelisted themes
    case forest
    case paper
    case coverGlass
    case classic
    case kleinSage
    case inkwash
    case porcelain
    case inkstone
    case hardcoverStudy
    case pineSootMagazine
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

    static let whitelistedCoreThemes: [Self] = [
        .forest, .paper, .coverGlass, .classic, .kleinSage, .inkwash,
        .porcelain, .inkstone, .hardcoverStudy, .pineSootMagazine
    ]
    static let atmosphericThemes: [Self] = [.shuimo, .wuxia, .anime, .kawaii]
    static let referenceThemes: [Self] = [.porcelain, .inkstone, .hardcoverStudy, .pineSootMagazine]
    var usesReferenceLayout: Bool { Self.referenceThemes.contains(self) }
    var usesEditorialPaper: Bool { self == .inkstone || self == .pineSootMagazine }

    static let classicDeskThemes: [Self] = [.classic, .kleinSage, .anime, .kawaii, .hardcoverStudy, .pineSootMagazine, .custom]
    static let floatingBookThemes: [Self] = [.forest, .paper, .coverGlass, .inkwash, .shuimo, .wuxia, .porcelain, .inkstone]
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
        case .forest, .paper, .coverGlass, .classic, .porcelain, .hardcoverStudy, .shuimo, .custom: return .readingDesk
        case .kleinSage, .wuxia, .inkstone, .pineSootMagazine: return .editorial
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
        let savedTheme = defaults.string(forKey: selectionKey).flatMap { $0.isEmpty ? nil : $0 }
        let wasClassic = defaults.bool(forKey: BookshelfStore.welcomeSeedPreferenceKey)
            || ["accent", "secondaryAccent"].contains { defaults.object(forKey: Self.classic.preferenceKey($0)) != nil }
        let isExistingInstall = savedTheme != nil || wasClassic
            || defaults.object(forKey: HomeBookPresentation.storageKey) != nil
        HomeBookPresentation.bootstrapSelection(in: defaults)
        if let raw = savedTheme {
            if Self(rawValue: raw) == nil {
                defaults.set(legacyFallback.rawValue, forKey: selectionKey)
            }
            return
        }
        let selection: Self = wasClassic ? .classic : isExistingInstall ? .forest : initialSelection
        defaults.set(selection.rawValue, forKey: selectionKey)
    }

    var title: String {
        switch self {
        case .forest: return "森林绿"
        case .paper: return "素纸 · 灰白"
        case .coverGlass: return "书影玻璃"
        case .classic: return "纸间 · 原初（白紫）"
        case .kleinSage: return "蓝艾 · 海报书刊"
        case .inkwash: return "水墨留白"
        case .porcelain: return "无界瓷白"
        case .inkstone: return "东方宣砚"
        case .hardcoverStudy: return "温润精装书房"
        case .pineSootMagazine: return "松烟杂志"
        case .shuimo: return "雾纸 · 水墨"
        case .wuxia: return "断锋 · 武侠"
        case .anime: return "晴空小镇"
        case .kawaii: return "兔兔书铺"
        case .custom: return "自定义主题工坊"
        }
    }

    var detail: String {
        switch self {
        case .forest: return "近白纸面透出淡绿，主页与其他页面同色"
        case .paper: return "F4F4F4 灰白底色 · 纯白卡片 · 中性玻璃"
        case .coverGlass: return "跟随主页书封吸色 · 全局柔雾玻璃 · 缓存背景"
        case .classic: return "原有白紫经典搭配 · 柔和圆角 · 轻透卡片"
        case .kleinSage: return "克莱因蓝 × 艾绿 · 清晰分栏 · 极夜深蓝护目"
        case .inkwash: return "山水留白 · 宣纸微影 · 极简墨线排布"
        case .porcelain: return "瓷白留白 · 薄透书托 · 让封面成为主角"
        case .inkstone: return "棉宣斜光 · 洞石书案 · 青玉细节"
        case .hardcoverStudy: return "淡绿透光 · 精装陈列 · 白色书托"
        case .pineSootMagazine: return "松烟墨色 · 编辑分栏 · 克制细线"
        case .shuimo: return "黑白宣墨 · 印章边框与游舟滑轨"
        case .wuxia: return "雾山黑白 · 飞白剑锋与八角墨签"
        case .anime: return "檐下的晴空与靛蓝夜色"
        case .kawaii: return "草莓兔兔 · 软萌兔耳与手账虚线"
        case .custom:
            let preset = AppCustomThemeStore.currentPreset
            return "\(preset.name) · \(preset.backdropKind.title) · 支持相册选图与一键配色"
        }
    }

    var accentHex: UInt32 {
        switch self {
        case .forest, .paper, .coverGlass: return 0x3D6348
        case .porcelain: return 0x3C5158
        case .inkstone: return 0x41564A
        case .hardcoverStudy: return 0x3D6348
        case .pineSootMagazine: return 0x35443B
        case .classic: return 0x594FDB
        case .kleinSage: return 0x012696
        case .inkwash: return 0x2F3B36
        case .shuimo: return 0x181818
        case .wuxia: return 0x0A0A0A
        case .anime: return 0x344F87
        case .kawaii: return 0xCF2E68
        case .custom: return AppCustomThemeStore.currentPreset.lightAccentHex
        }
    }

    var secondaryHex: UInt32 {
        switch self {
        case .forest, .paper, .coverGlass: return 0x526458
        case .porcelain: return 0x5E6D72
        case .inkstone: return 0x616B62
        case .hardcoverStudy: return 0x526458
        case .pineSootMagazine: return 0x657068
        case .classic: return 0x419BDC
        case .kleinSage: return 0x855A0C
        case .inkwash: return 0x6B7470
        case .shuimo: return 0x4F4F4F
        case .wuxia: return 0x3D3D3D
        case .anime: return 0x9A5467
        case .kawaii: return 0xE66495
        case .custom: return AppCustomThemeStore.currentPreset.lightSecondaryHex
        }
    }

    var darkAccentHex: UInt32 {
        switch self {
        case .forest, .paper, .coverGlass: return 0xBAD6C0
        case .porcelain: return 0xD2E0E4
        case .inkstone: return 0xD3DDD0
        case .hardcoverStudy: return 0xBAD6C0
        case .pineSootMagazine: return 0xD7E0D8
        case .classic: return 0xB8B3FF
        case .kleinSage: return 0x9DB4FF
        case .inkwash: return 0xC8D3CD
        case .shuimo: return 0xF2F2F2
        case .wuxia: return 0xFFFFFF
        case .anime: return 0xADC2F5
        case .kawaii: return 0xFF9AC2
        case .custom: return AppCustomThemeStore.currentPreset.darkAccentHex
        }
    }

    var darkSecondaryHex: UInt32 {
        switch self {
        case .forest, .paper, .coverGlass: return 0xAEBBB2
        case .porcelain: return 0xA8BAC0
        case .inkstone: return 0xADB9B0
        case .hardcoverStudy: return 0xAEBBB2
        case .pineSootMagazine: return 0xB4C1B8
        case .classic: return 0x76C4FF
        case .kleinSage: return 0xFFD97A
        case .inkwash: return 0x9AA6A0
        case .shuimo: return 0xA8A8A8
        case .wuxia: return 0xB8B8B8
        case .anime: return 0xD3AEBF
        case .kawaii: return 0xF5B3CF
        case .custom: return AppCustomThemeStore.currentPreset.darkSecondaryHex
        }
    }

    var backgroundHex: UInt32 {
        switch self {
        case .forest, .coverGlass: return 0xFFFFFF
        case .paper: return 0xF4F4F4
        case .classic: return 0xF2F2F7
        case .kleinSage: return 0xF0F5F7
        case .inkwash: return 0xF7F6F1
        case .porcelain: return 0xF4F7F8
        case .inkstone: return 0xF6F4ED
        case .hardcoverStudy: return 0xEFF5F1
        case .pineSootMagazine: return 0xF4F6F3
        case .shuimo: return 0xF5F5F5
        case .wuxia: return 0xECECEC
        case .anime: return 0xEDF1F8
        case .kawaii: return 0xFFF2F6
        case .custom: return AppCustomThemeStore.currentPreset.lightBackgroundHex
        }
    }

    var cardHex: UInt32 {
        switch self {
        case .forest, .paper, .coverGlass: return 0xFFFFFF
        case .classic: return 0xFFFFFF
        case .kleinSage: return 0xFAFFFC
        case .inkwash: return 0xFCFAF4
        case .porcelain: return 0xFCFEFE
        case .inkstone: return 0xFBFAF5
        case .hardcoverStudy: return 0xFCFEFC
        case .pineSootMagazine: return 0xFBFCFA
        case .shuimo: return 0xFFFFFF
        case .wuxia: return 0xFFFFFF
        case .anime: return 0xF8F9FD
        case .kawaii: return 0xFFFFFF
        case .custom: return AppCustomThemeStore.currentPreset.lightCardHex
        }
    }

    var darkBackgroundHex: UInt32 {
        switch self {
        case .forest, .coverGlass: return 0x151716
        case .paper: return 0x000000
        case .classic: return 0x000000
        case .kleinSage: return 0x0A1231
        case .inkwash: return 0x101312
        case .porcelain: return 0x101619
        case .inkstone: return 0x141714
        case .hardcoverStudy: return 0x151C18
        case .pineSootMagazine: return 0x141715
        case .shuimo: return 0x101010
        case .wuxia: return 0x090909
        case .anime: return 0x141A30
        case .kawaii: return 0x201319
        case .custom: return AppCustomThemeStore.currentPreset.darkBackgroundHex
        }
    }

    var darkCardHex: UInt32 {
        switch self {
        case .forest, .coverGlass: return 0x222423
        case .paper: return 0x161616
        case .classic: return 0x1C1C1E
        case .kleinSage: return 0x172344
        case .inkwash: return 0x1B1F1E
        case .porcelain: return 0x1D2629
        case .inkstone: return 0x222620
        case .hardcoverStudy: return 0x202A23
        case .pineSootMagazine: return 0x212522
        case .shuimo: return 0x191919
        case .wuxia: return 0x141414
        case .anime: return 0x202943
        case .kawaii: return 0x2D1B24
        case .custom: return AppCustomThemeStore.currentPreset.darkCardHex
        }
    }

    var radius: CGFloat {
        switch self {
        case .forest: return 22
        case .paper: return 14
        case .coverGlass: return 16
        case .classic: return 18
        case .kleinSage: return 8
        case .inkwash: return 12
        case .porcelain: return 16
        case .inkstone: return 12
        case .hardcoverStudy: return 26
        case .pineSootMagazine: return 8
        case .shuimo: return 10
        case .wuxia: return 6
        case .anime: return 24
        case .kawaii: return 20
        case .custom: return CGFloat(AppCustomThemeStore.currentPreset.cornerRadius)
        }
    }

    var usesNeutralGlass: Bool {
        switch self {
        case .forest, .paper, .coverGlass, .porcelain, .inkstone, .hardcoverStudy, .pineSootMagazine: return true
        default: return false
        }
    }
    var usesTintedPaper: Bool { self == .forest || self == .coverGlass }
    var mistPaper: Color { dynamicColor(light: 0xFDFEFD, dark: 0x181B19) }
    var mistTint: Color { dynamicColor(light: 0xE7F0EB, dark: 0x26332B) }
    func glassCardOpacity(reducesTransparency: Bool, increasedContrast: Bool) -> Double {
        usesTintedPaper && !reducesTransparency && !increasedContrast ? 0.64 : 1
    }
    var isMonochromeEdition: Bool { self == .shuimo || self == .wuxia }

    var supportsLiveGlass: Bool {
        switch self {
        case .inkwash, .coverGlass: return false
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

    var primaryInk: Color {
        switch self {
        case .forest: return dynamicColor(light: 0x1C211D, dark: 0xF0F2EF)
        case .paper, .coverGlass: return dynamicColor(light: 0x111111, dark: 0xF5F5F5)
        case .porcelain: return dynamicColor(light: 0x20292C, dark: 0xF1F5F6)
        case .inkstone: return dynamicColor(light: 0x282D29, dark: 0xF2F2EB)
        case .hardcoverStudy: return dynamicColor(light: 0x243129, dark: 0xEFF5F0)
        case .pineSootMagazine: return dynamicColor(light: 0x262D29, dark: 0xF0F3F0)
        default: return .primary
        }
    }
    var secondaryInk: Color {
        switch self {
        case .forest: return dynamicColor(light: 0x49534B, dark: 0xABB1AB)
        case .paper: return dynamicColor(light: 0x595959, dark: 0xA3A3A3)
        case .coverGlass: return dynamicColor(light: 0x191919, dark: 0xD5D8D5)
        case .porcelain: return dynamicColor(light: 0x526166, dark: 0xB5C2C6)
        case .inkstone: return dynamicColor(light: 0x59645B, dark: 0xB5C0B6)
        case .hardcoverStudy: return dynamicColor(light: 0x526458, dark: 0xBAC8BE)
        case .pineSootMagazine: return dynamicColor(light: 0x59665E, dark: 0xB8C4BC)
        default: return .secondary
        }
    }
    var selectionSurfaceHex: UInt32 {
        switch self {
        case .paper: return 0xEDEDED
        case .porcelain: return 0xEEF2F3
        case .inkstone: return 0xEFEFEA
        case .hardcoverStudy: return 0xE4EEE7
        case .pineSootMagazine: return 0xEDEFEB
        default: return 0xF3F3F0
        }
    }
    var neutralBorderHex: UInt32 {
        switch self {
        case .paper: return 0xE6E6E6
        case .porcelain: return 0xE1E8EA
        case .inkstone: return 0xE4E2D9
        case .hardcoverStudy: return 0xDDE7E0
        case .pineSootMagazine: return 0xE1E6E0
        default: return 0xE6E8E3
        }
    }
    var controlFill: Color { dynamicColor(light: selectionSurfaceHex, dark: self == .paper ? 0x242424 : 0x303430) }
    var controlBorder: Color { dynamicColor(light: neutralBorderHex, dark: self == .paper ? 0x262626 : 0x414641) }

    var borderWidth: CGFloat {
        switch self {
        case .forest: return 0
        case .paper: return 0.5
        case .wuxia, .kleinSage: return 0.9
        default: return 0.6
        }
    }

    var fontDesign: Font.Design {
        switch self {
        case .anime, .kawaii: return .rounded
        case .inkwash, .shuimo, .wuxia, .inkstone, .pineSootMagazine: return .serif
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
        case .paper: return "rectangle"
        case .coverGlass: return "rectangle.on.rectangle"
        case .classic: return "book.closed"
        case .kleinSage: return "square.split.2x2"
        case .inkwash: return "mountain.2"
        case .porcelain: return "square.on.square"
        case .inkstone: return "pencil.tip"
        case .hardcoverStudy: return "books.vertical"
        case .pineSootMagazine: return "text.alignleft"
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
    @AppStorage(PersonalBrandMarkStore.enabledKey) private var usesPhoto = false
    @AppStorage(PersonalBrandMarkStore.frameKey) private var frameRaw = PersonalBrandMarkStore.Frame.full.rawValue
    @ObservedObject private var personalMark = PersonalBrandMarkStore.shared

    var body: some View {
        let asset = AppIconOption.resolved(rawValue: selectedIconRaw).brandMarkAssetName
        let photoFrame = PersonalBrandMarkStore.Frame(rawValue: frameRaw) ?? .full
        let photo = usesPhoto ? personalMark.image : nil
        (photo.map { Image(uiImage: $0) } ?? Image(asset))
            .resizable().interpolation(.high).scaledToFit()
            .padding(photo == nil ? 0 : size * photoFrame.insetFraction)
            .frame(width: size, height: size)
            .background(photo == nil ? AppTheme.card : Color(uiColor: PersonalBrandMarkStore.Frame.paper))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .stroke(.primary.opacity(0.08), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
            .accessibilityHidden(true)
            .task(id: usesPhoto) {
                if usesPhoto { await personalMark.loadIfNeeded() }
            }
    }
}
