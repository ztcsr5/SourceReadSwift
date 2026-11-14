import Foundation
import SwiftUI
import UIKit

enum ReaderBackground: String, CaseIterable, Identifiable, Codable, Sendable {
    case paper      // 羊皮纸暖黄 (#EBD9BB)
    case kraftTexture
    case parchmentTexture
    case linen
    case bamboo, mountains, ginkgo, tide
    case sageGreen   // 松烟豆绿 (#D5E6D4)
    case shuimoPaper // 水墨丹青（日夜双画）
    case wuxiaScroll // 江湖古卷（日夜双画）
    case starlight   // 星夜碎金（深空星座）
    case sakuraSky   // 晴空樱笺（日夜双画）
    case kawaiiNote  // 奶油手账（日夜双画）
    case paperCats, moonLetters, cloudIslands, starPlanes
    case kraft      // 复古牛皮 (#DDC090)
    case green      // 豆沙青绿 (#C2D8AA)
    case lavender   // 淡雅黛紫 (#DBB8E2)
    case azure      // 晴空天蓝 (#ABCEE0)
    case white      // 纯净素白 (#FFFFFF)
    case gray       // 浅灰银质 (#F2F2F7)
    case dark       // 极夜纯黑 (#000000)
    case eink       // 电子水墨 (#FFFFFF / #000000 高对比度)
    case custom     // 自定义壁纸

    // Sakura 主题调色板（与 SakuraThemeCatalog CSS 一一对应）
    case sakuraClassic
    case sakuraDark
    case sakuraSolarized
    case sakuraEarthly
    case sakuraInk
    case sakuraVader

    var id: String { rawValue }

    /// 外观面板里真正展示的精品阅读背景。
    /// `allCases` 保留全部历史取值用于解码旧设置，pickerCases 精简同质纯色块、聚焦高颜值纸纹与日夜双绘背景。
    static var pickerCases: [ReaderBackground] {
        [
            .white,      // 素白
            .paper,      // 羊皮纸
            .sageGreen,  // 松烟豆绿（P3 经典护眼）
            .green,      // 豆沙绿
            .shuimoPaper,// 水墨丹青
            .wuxiaScroll,// 江湖古卷
            .starlight,  // 星夜碎金
            .sakuraSky,  // 晴空樱笺
            .kawaiiNote, // 奶油手账
            .bamboo,     // 竹影宣纸
            .mountains,  // 远山雾白
            .ginkgo,     // 银杏花笺
            .tide,       // 浅海潮汐
            .paperCats,  // 猫咪借书处
            .moonLetters,// 月亮邮局
            .cloudIslands,// 云朵小岛
            .starPlanes, // 星屑纸飞机
            .kraftTexture,// 牛皮纸纹
            .linen,      // 亚麻纸纹
            .dark,       // 极夜玄墨
            .custom      // 自定义壁纸与联动配色
        ]
    }

    var title: String {
        switch self {
        case .paper: return "羊皮纸"
        case .kraft: return "牛皮色"
        case .kraftTexture: return "牛皮纸纹"
        case .parchmentTexture: return "羊皮纸纹"
        case .linen: return "亚麻纸纹"
        case .bamboo: return "竹影宣纸"
        case .mountains: return "远山雾白"
        case .ginkgo: return "银杏花笺"
        case .tide: return "浅海潮汐"
        case .sageGreen: return "松烟豆绿"
        case .shuimoPaper: return "水墨丹青"
        case .wuxiaScroll: return "江湖古卷"
        case .starlight: return "星夜碎金"
        case .sakuraSky: return "晴空樱笺"
        case .kawaiiNote: return "奶油手账"
        case .paperCats: return "猫咪借书处"
        case .moonLetters: return "月亮邮局"
        case .cloudIslands: return "云朵小岛"
        case .starPlanes: return "星屑纸飞机"
        case .green: return "豆沙绿"
        case .lavender: return "黛紫"
        case .azure: return "青空"
        case .white: return "素白"
        case .gray: return "浅灰"
        case .dark: return "极黑"
        case .eink: return "水墨屏"
        case .custom: return "自定义"
        case .sakuraClassic: return "樱白"
        case .sakuraDark: return "夜樱"
        case .sakuraSolarized: return "暖阳"
        case .sakuraEarthly: return "大地"
        case .sakuraInk: return "墨白"
        case .sakuraVader: return "深渊"
        }
    }

    var hasTexture: Bool {
        self == .kraftTexture || self == .parchmentTexture || self == .linen
            || wallpaperAssetName != nil || doodlePattern != nil
    }

    var doodlePattern: ReaderDoodlePattern? {
        switch self {
        case .paperCats: return .cats
        case .moonLetters: return .letters
        case .cloudIslands: return .clouds
        case .starPlanes: return .planes
        default: return nil
        }
    }

    var wallpaperAssetName: String? {
        wallpaperAssetName(isNight: false)
    }

    func wallpaperAssetName(isNight: Bool) -> String? {
        switch self {
        case .bamboo: return "ReadingBamboo"
        case .mountains: return "ReadingMountains"
        case .ginkgo: return "ReadingGinkgo"
        case .tide: return "ReadingTide"
        case .starlight: return "ReadingStarlight"
        case .shuimoPaper: return isNight ? "ThemeShuimoNight" : "ThemeShuimoDay"
        case .wuxiaScroll: return isNight ? "ThemeWuxiaNight" : "ThemeWuxiaDay"
        case .sakuraSky: return isNight ? "ThemeAnimeNight" : "ThemeAnimeDay"
        case .kawaiiNote: return isNight ? "ThemeKawaiiNight" : "ThemeKawaiiDay"
        default: return nil
        }
    }

    var hasDedicatedNightAsset: Bool {
        switch self {
        case .starlight, .shuimoPaper, .wuxiaScroll, .sakuraSky, .kawaiiNote:
            return true
        default:
            return false
        }
    }

    var color: Color {
        color(isNight: false)
    }

    var textColor: Color {
        textColor(isNight: false)
    }

    func dynamicColor(isNight: Bool) -> Color {
        color(isNight: isNight)
    }

    func dynamicTextColor(isNight: Bool) -> Color {
        textColor(isNight: isNight)
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
        case .paper, .parchmentTexture: return 0xEBD9BB
        case .kraft, .kraftTexture: return 0xDDC090
        case .linen: return 0xF1EBDD
        case .bamboo: return 0xEFF2E3
        case .mountains: return 0xF5F3EB
        case .ginkgo: return 0xF8F1E7
        case .tide: return 0xEFF5F7
        case .paperCats: return 0xF9F3E9
        case .moonLetters: return 0xF2F0FA
        case .cloudIslands: return 0xEEF5F8
        case .starPlanes: return 0xF3F6EC
        case .sageGreen: return 0xD5E6D4
        case .shuimoPaper: return 0xF5F1E8
        case .wuxiaScroll: return 0xEFE7D6
        case .starlight: return 0x18202E
        case .sakuraSky: return 0xF9F0F4
        case .kawaiiNote: return 0xFBF1EC
        case .green: return 0xC2D8AA
        case .lavender: return 0xDBB8E2
        case .azure: return 0xABCEE0
        case .white, .eink: return 0xFFFFFF
        case .gray: return 0xF2F2F7
        case .dark: return 0x000000
        case .custom: return isDark ? 0x1C1C1E : 0xF7F7F8
        case .sakuraClassic: return 0xF9F9F9
        case .sakuraDark: return 0x222222
        case .sakuraSolarized: return 0x002B36
        case .sakuraEarthly: return 0xFFFFFF
        case .sakuraInk: return 0xFFFFFF
        case .sakuraVader: return 0x120C0E
        }
    }

    var dayTextHex: UInt32 {
        switch self {
        case .paper, .parchmentTexture: return 0x63543C
        case .kraft, .kraftTexture: return 0x3E3422
        case .linen: return 0x38342F
        case .bamboo, .mountains, .ginkgo, .tide, .paperCats, .moonLetters, .cloudIslands, .starPlanes: return 0x222A25
        case .sageGreen: return 0x233325
        case .shuimoPaper: return 0x24282B
        case .wuxiaScroll: return 0x2C231A
        case .starlight: return 0xEDE6D6
        case .sakuraSky: return 0x2D2732
        case .kawaiiNote: return 0x3C2D2F
        case .green: return 0x596C44
        case .lavender: return 0x5A4761
        case .azure: return 0x345367
        case .white: return 0x18181A
        case .gray: return 0x242426
        case .eink: return 0x000000
        case .dark: return 0xFFFFFF
        case .custom: return isDark ? 0xFFFFFF : 0x18181A
        case .sakuraClassic: return 0x4A4A4A
        case .sakuraDark: return 0xC9C9C9
        case .sakuraSolarized: return 0x839496
        case .sakuraEarthly: return 0x222222
        case .sakuraInk: return 0x262626
        case .sakuraVader: return 0xD9D8DC
        }
    }

    var nightBackgroundHex: UInt32 {
        switch self {
        case .paper, .parchmentTexture: return 0x1E2021
        case .kraft, .kraftTexture, .linen, .green, .lavender, .azure: return 0x3C3F43
        case .bamboo, .mountains, .ginkgo, .tide, .paperCats, .moonLetters, .cloudIslands, .starPlanes: return 0x1D2420
        case .sageGreen: return 0x1A261E
        case .shuimoPaper: return 0x161B20
        case .wuxiaScroll: return 0x141819
        case .starlight: return 0x18202E
        case .sakuraSky: return 0x181B2C
        case .kawaiiNote: return 0x251C22
        case .white: return 0x18181A
        case .gray: return 0x2C2C2E
        case .dark, .eink: return 0x000000
        case .custom: return 0x1C1C1E
        case .sakuraClassic: return 0x1C1C1E
        case .sakuraDark: return 0x222222
        case .sakuraSolarized: return 0x002B36
        case .sakuraEarthly: return 0x18211D
        case .sakuraInk: return 0x000000
        case .sakuraVader: return 0x120C0E
        }
    }

    var nightTextHex: UInt32 {
        switch self {
        case .paper, .kraft, .parchmentTexture, .kraftTexture, .linen: return 0xDCDFE1
        case .bamboo, .mountains, .ginkgo, .tide, .paperCats, .moonLetters, .cloudIslands, .starPlanes: return 0xDEE4DF
        case .sageGreen: return 0xD6E6D7
        case .shuimoPaper: return 0xDDE2E6
        case .wuxiaScroll: return 0xDCD4C4
        case .starlight: return 0xE6DFCF
        case .sakuraSky: return 0xEAE8F4
        case .kawaiiNote: return 0xEFE0DF
        case .green: return 0x88C16F
        case .lavender: return 0xF6AEAE
        case .azure: return 0x90BFF5
        case .white: return 0xE0E0E0
        case .gray: return 0xF2F2F7
        case .dark, .eink: return 0xFFFFFF
        case .custom: return 0xFFFFFF
        case .sakuraClassic: return 0xD8D8D8
        case .sakuraDark: return 0xC9C9C9
        case .sakuraSolarized: return 0x839496
        case .sakuraEarthly: return 0xD3DAD5
        case .sakuraInk: return 0xFFFFFF
        case .sakuraVader: return 0xD9D8DC
        }
    }

    var recommendedAccentHex: UInt32 {
        switch self {
        case .shuimoPaper: return 0x9E3B33
        case .wuxiaScroll: return 0x4A6B62
        case .starlight: return 0xD6B46A
        case .sakuraSky: return 0xC85A82
        case .kawaiiNote: return 0xD96B85
        case .sageGreen, .green: return 0x3D6B52
        case .custom:
            return ReaderCustomWallpaperStore.adjustment.linkedAccentHex ?? 0x3D6B52
        default:
            return 0x3D6B52
        }
    }

    func resolvedTextHex(isNight: Bool, customInkHex: UInt32? = nil) -> UInt32 {
        if let customInkHex { return customInkHex }
        if self == .custom {
            let adj = ReaderCustomWallpaperStore.adjustment
            if isNight, let linkedNight = adj.linkedNightInkHex { return linkedNight }
            if !isNight, let linkedDay = adj.linkedInkHex { return linkedDay }
        }
        return isNight ? nightTextHex : dayTextHex
    }

    func resolvedUITextColor(isNight: Bool, customInkHex: UInt32? = nil, inkOpacity: Double = 1.0) -> UIColor {
        let base = UIColor(hex: resolvedTextHex(isNight: isNight, customInkHex: customInkHex))
        let clamped = min(max(inkOpacity.isFinite ? inkOpacity : 1.0, 0.55), 1.0)
        return clamped >= 0.999 ? base : base.withAlphaComponent(clamped)
    }

    func resolvedTextColor(isNight: Bool, customInkHex: UInt32? = nil, inkOpacity: Double = 1.0) -> Color {
        Color(uiColor: resolvedUITextColor(isNight: isNight, customInkHex: customInkHex, inkOpacity: inkOpacity))
    }

    var isDark: Bool {
        switch self {
        case .dark, .starlight, .sakuraDark, .sakuraSolarized, .sakuraVader:
            return true
        case .custom:
            return ReaderCustomWallpaperStore.isWallpaperDark
        default:
            return false
        }
    }

    func darkStatusIcon(isNight: Bool) -> Bool {
        if isNight { return false }
        switch self {
        case .paper, .kraft, .parchmentTexture, .kraftTexture, .linen, .white, .gray, .eink,
             .sakuraClassic, .sakuraEarthly, .sakuraInk, .bamboo, .mountains, .ginkgo, .tide,
             .sageGreen, .shuimoPaper, .wuxiaScroll, .sakuraSky, .kawaiiNote,
             .paperCats, .moonLetters, .cloudIslands, .starPlanes: return true
        case .custom:
            return !isDark
        case .green, .lavender, .azure, .dark, .starlight,
             .sakuraDark, .sakuraSolarized, .sakuraVader: return false
        }
    }

    /// 与 SakuraThemeCatalog 的 CSS 主题一一映射；非 Sakura 调色板返回 nil。
    var sakuraTheme: SakuraThemeCatalog.Theme? {
        switch self {
        case .sakuraClassic: return .classic
        case .sakuraDark: return .dark
        case .sakuraSolarized: return .solarized
        case .sakuraEarthly: return .earthly
        case .sakuraInk: return .ink
        case .sakuraVader: return .vader
        default: return nil
        }
    }

    init(sakuraTheme: SakuraThemeCatalog.Theme) {
        switch sakuraTheme {
        case .classic: self = .sakuraClassic
        case .dark: self = .sakuraDark
        case .solarized: self = .sakuraSolarized
        case .earthly: self = .sakuraEarthly
        case .ink: self = .sakuraInk
        case .vader: self = .sakuraVader
        }
    }
}

extension UIImage {
    /// 分析壁纸相对感知亮度（Rec. 709标准），用于自适应决定深浅文字风格与对比度。
    var isDarkPerception: Bool {
        if let cgImage = self.cgImage {
            return Self.analyzeLuminance(cgImage: cgImage)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format)
        let smallImage = renderer.image { _ in
            self.draw(in: CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        if let cgImage = smallImage.cgImage {
            return Self.analyzeLuminance(cgImage: cgImage)
        }
        return false
    }

    private static func analyzeLuminance(cgImage: CGImage) -> Bool {
        let width = 8
        let height = 8
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return false }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var totalLuminance: Double = 0
        let totalPixels = width * height
        for i in 0..<totalPixels {
            let r = Double(rawData[i * 4]) / 255.0
            let g = Double(rawData[i * 4 + 1]) / 255.0
            let b = Double(rawData[i * 4 + 2]) / 255.0
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            totalLuminance += luma
        }
        let avg = totalLuminance / Double(totalPixels)
        return avg < 0.52
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xff) / 255.0
        let green = Double((hex >> 8) & 0xff) / 255.0
        let blue = Double(hex & 0xff) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let red = CGFloat((hex >> 16) & 0xff) / 255.0
        let green = CGFloat((hex >> 8) & 0xff) / 255.0
        let blue = CGFloat(hex & 0xff) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

enum ReaderMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case scroll
    case pageTurn
    case cover
    case pageCurl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scroll: return "滑动"
        case .pageTurn: return "平移"
        case .cover: return "覆盖"
        case .pageCurl: return "仿真"
        }
    }
}

enum ReaderFontFamily: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case light
    case bold
    case songti
    case kaiti
    case rounded
    case maShanZheng
    case zhiMangXing
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "常规"
        case .light: return "细体"
        case .bold: return "粗体"
        case .songti: return "宋体"
        case .kaiti: return "楷体"
        case .rounded: return "圆体"
        case .maShanZheng: return "马善政楷书"
        case .zhiMangXing: return "志莽行书"
        case .custom: return "自定义"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? "system"
        switch raw {
        case "light": self = .light
        case "bold": self = .bold
        case "songti": self = .songti
        case "kaiti": self = .kaiti
        case "rounded": self = .rounded
        case "maShanZheng": self = .maShanZheng
        case "zhiMangXing": self = .zhiMangXing
        case "custom": self = .custom
        default: self = .system
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    func uiFont(ofSize size: CGFloat, weight: UIFont.Weight = .regular, customPostScriptName: String? = nil) -> UIFont {
        switch self {
        case .system:
            return UIFont.systemFont(ofSize: size, weight: weight)
        case .light:
            return UIFont.systemFont(ofSize: size, weight: .light)
        case .bold:
            return UIFont.systemFont(ofSize: size, weight: .bold)
        case .songti:
            let songtiNames = weight == .bold || weight == .semibold
                ? ["Songti SC Bold", "SongtiSC-Bold", "STSongti-SC-Bold", "HiraMinProN-W6", "STSong", "ReadingDeskSong-Regular"]
                : weight == .light || weight == .thin
                    ? ["STSongti-SC-Light", "HiraMinProN-W3", "Songti SC Regular", "ReadingDeskSong-Regular"]
                    : ["Songti SC Regular", "Songti SC", "SongtiSC-Regular", "STSongti-SC-Regular", "HiraMinProN-W3", "ReadingDeskSong-Regular"]
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
                ? ["Kaiti SC Bold", "KaitiSC-Bold", "STKaiti-SC-Bold", "STKaiti"]
                : ["Kaiti SC Regular", "Kaiti SC", "KaitiSC-Regular", "STKaiti-SC-Regular", "STKaiti", "KaiTi"]
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
        case .maShanZheng, .zhiMangXing:
            let name = self == .maShanZheng ? "MaShanZheng-Regular" : "ZhiMangXing-Regular"
            return UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)
        case .custom:
            let psName = customPostScriptName ?? UserDefaults.standard.string(forKey: "reader.customFontPostScriptName")
            if let psName, !psName.isEmpty, let font = UIFont(name: psName, size: size) {
                return font
            }
            return UIFont.systemFont(ofSize: size, weight: weight)
        }
    }

    func swiftUIFont(size: CGFloat, weight: Font.Weight = .regular, customPostScriptName: String? = nil) -> Font {
        switch self {
        case .system:
            return .system(size: size, weight: weight, design: .default)
        case .light:
            return .system(size: size, weight: .light, design: .default)
        case .bold:
            return .system(size: size, weight: .bold, design: .default)
        case .songti:
            let songtiNames = weight == .bold || weight == .semibold
                ? ["Songti SC Bold", "SongtiSC-Bold", "STSongti-SC-Bold", "HiraMinProN-W6", "ReadingDeskSong-Regular"]
                : ["Songti SC Regular", "Songti SC", "SongtiSC-Regular", "STSongti-SC-Regular", "HiraMinProN-W3", "ReadingDeskSong-Regular"]
            for name in songtiNames {
                if UIFont(name: name, size: size) != nil {
                    return .custom(name, size: size)
                }
            }
            return .system(size: size, weight: weight, design: .serif)
        case .kaiti:
            let kaitiNames = weight == .bold
                ? ["Kaiti SC Bold", "KaitiSC-Bold", "STKaiti-SC-Bold", "STKaiti"]
                : ["Kaiti SC Regular", "Kaiti SC", "KaitiSC-Regular", "STKaiti-SC-Regular", "STKaiti"]
            for name in kaitiNames {
                if UIFont(name: name, size: size) != nil {
                    return .custom(name, size: size)
                }
            }
            return .system(size: size, weight: weight, design: .serif)
        case .rounded:
            return .system(size: size, weight: weight, design: .rounded)
        case .maShanZheng, .zhiMangXing:
            return .custom(self == .maShanZheng ? "MaShanZheng-Regular" : "ZhiMangXing-Regular", size: size)
        case .custom:
            let psName = customPostScriptName ?? UserDefaults.standard.string(forKey: "reader.customFontPostScriptName")
            if let psName, !psName.isEmpty, UIFont(name: psName, size: size) != nil {
                return .custom(psName, size: size)
            }
            return .system(size: size, weight: weight, design: .default)
        }
    }
}

enum ReaderTypographyDefaults {
    // 对标 390×844pt 竞品截图：正文 20pt、左右边距 21pt、首行缩进 2 字。
    // 段距必须大于行距，否则整屏文字会连成一片：行内额外 leading 8pt，
    // 段后 16pt（2 倍）。RSS 正文一直用的就是 8 / 16。
    static let fontSize: Double = 20
    static let lineSpacing: Double = 8
    static let letterSpacing: Double = 0
    static let paragraphSpacing: Double = 16
    static let paragraphIndent: Double = 40 // 2 characters * 20pt
    static let titleSpacing: Double = 12
    static let pagePadding: Double = 21
    static let footerHeight: Double = 72

    /// Title text must stay clearly larger than body text at every font size.
    static func titleFontSize(for bodySize: Double) -> Double {
        max(bodySize * 1.30, bodySize + 6)
    }
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
    // Five chapters on each side matches the continuous-read contract.
    static let defaultCount = 5
    static let minimumCount = 0
    static let maximumCount = 5

    static func clamp(_ count: Int) -> Int {
        min(max(count, minimumCount), maximumCount)
    }

    static func title(for count: Int) -> String {
        let value = clamp(count)
        return value == 0 ? "仅相邻 1 章" : "前后各 \(value) 章"
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
            .multilineTextAlignment(.center)
            .textFieldStyle(.plain)
            .foregroundStyle(.primary)
            // 系统深色模式下 .roundedBorder 会渲染成纯黑方块，和阅读面板脱节；
            // 改用主题中性的半透明底 + 圆角，深浅背景下都可读。
            .frame(width: 56, height: 30)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.6)
            }
            .focused($focused)
            .accessibilityLabel("输入\(title)")

            Text(unit)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 13, alignment: .leading)
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

enum ReaderTextAlignment: String, CaseIterable, Identifiable, Codable, Sendable {
    case smart
    case justified
    case leading

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: return "避头尾精排"
        case .justified: return "两端对齐"
        case .leading: return "左对齐"
        }
    }

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .smart, .justified: return .justified
        case .leading: return .left
        }
    }

    var cssTextAlign: String {
        switch self {
        case .smart, .justified: return "justify"
        case .leading: return "left"
        }
    }

    var compressesPunctuation: Bool {
        self == .smart
    }
}

enum ReaderBodyFontWeight: String, CaseIterable, Identifiable, Codable, Sendable {
    case light
    case regular
    case medium
    case semibold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "细"
        case .regular: return "常规"
        case .medium: return "适中"
        case .semibold: return "加粗"
        }
    }

    var uiWeight: UIFont.Weight {
        switch self {
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        }
    }

    var swiftUIWeight: Font.Weight {
        switch self {
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        }
    }

    var cssWeight: Int {
        switch self {
        case .light: return 300
        case .regular: return 400
        case .medium: return 500
        case .semibold: return 600
        }
    }
}

enum ReaderTypographyPreset: String, CaseIterable, Identifiable, Sendable {
    case oneHandLarge
    case printClassic
    case bedtimeCompact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneHandLarge: return "单手大字"
        case .printClassic: return "纸书精排"
        case .bedtimeCompact: return "睡前紧凑"
        }
    }

    var subtitle: String {
        switch self {
        case .oneHandLarge: return "22pt · 疏朗护眼"
        case .printClassic: return "20pt · 实体书比例"
        case .bedtimeCompact: return "17pt · 高密省屏"
        }
    }

    var fontSize: Double {
        switch self {
        case .oneHandLarge: return 22
        case .printClassic: return 20
        case .bedtimeCompact: return 17
        }
    }

    var lineSpacing: Double {
        switch self {
        case .oneHandLarge: return 11
        case .printClassic: return 9
        case .bedtimeCompact: return 6
        }
    }

    var paragraphSpacing: Double {
        switch self {
        case .oneHandLarge: return 18
        case .printClassic: return 15
        case .bedtimeCompact: return 10
        }
    }

    var paragraphIndent: Double {
        switch self {
        case .oneHandLarge: return 44
        case .printClassic: return 40
        case .bedtimeCompact: return 34
        }
    }

    var pagePadding: Double {
        switch self {
        case .oneHandLarge: return 24
        case .printClassic: return 21
        case .bedtimeCompact: return 16
        }
    }

    var verticalPadding: Double {
        switch self {
        case .oneHandLarge: return 8
        case .printClassic: return 4
        case .bedtimeCompact: return 0
        }
    }
}
