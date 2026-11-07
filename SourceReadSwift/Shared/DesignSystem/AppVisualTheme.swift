import SwiftUI
import UIKit

/// A coordinated visual language, not a synonym for an accent colour.
enum AppVisualTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case forest, classic, botanical, editorial, coast, rose, graphite, folio, inkwash, blueprint
    var id: String { rawValue }
    static let selectionKey = "settings.visualTheme"
    static let initialSelection = Self.forest
    static let classicDeskThemes: [Self] = [.classic, .editorial, .graphite, .folio, .blueprint]
    static let floatingBookThemes: [Self] = [.forest, .botanical, .coast, .rose, .inkwash]

    var usesFloatingBook: Bool { Self.floatingBookThemes.contains(self) }
    enum HomeComposition: String, CaseIterable, Hashable { case readingDesk, editorial, index, gallery }
    var homeComposition: HomeComposition {
        switch self {
        case .editorial: return .editorial
        case .graphite, .blueprint: return .index
        case .folio: return .gallery
        default: return .readingDesk
        }
    }
    var compositionTitle: String {
        switch homeComposition {
        case .readingDesk: return "书台 · 三列藏书"
        case .editorial: return "书刊 · 分栏阅读卡"
        case .index: return "索引 · 紧凑目录"
        case .gallery: return "藏书票 · 双列陈列"
        }
    }
    var illustratedPaper: ReaderBackground? {
        switch self {
        case .botanical: return .bamboo
        case .coast: return .tide
        case .rose: return .ginkgo
        case .inkwash: return .mountains
        default: return nil
        }
    }
    static var current: Self { selected(in: .standard) }

    static func selected(in defaults: UserDefaults) -> Self {
        guard let raw = defaults.string(forKey: selectionKey) else { return initialSelection }
        return Self(rawValue: raw) ?? .classic
    }

    /// Preserve a stored choice verbatim. Decide once, before first-run shelf seeding.
    static func bootstrapSelection(in defaults: UserDefaults) {
        guard defaults.object(forKey: selectionKey) == nil else { return }
        let wasClassic = defaults.bool(forKey: BookshelfStore.welcomeSeedPreferenceKey)
            || ["accent", "secondaryAccent"].contains { defaults.object(forKey: Self.classic.preferenceKey($0)) != nil }
        defaults.set(wasClassic ? Self.classic.rawValue : initialSelection.rawValue, forKey: selectionKey)
    }
    var title: String {
        switch self {
        case .forest: return "森林绿"
        case .classic: return "纸间 · 原初（白紫）"
        case .botanical: return "草木书房"
        case .editorial: return "书刊编辑室"
        case .coast: return "海岸来信"
        case .rose: return "花笺手记"
        case .graphite: return "石墨工作台"
        case .folio: return "藏书票馆"
        case .inkwash: return "水墨留白"
        case .blueprint: return "蓝图书库"
        }
    }
    var detail: String {
        switch self {
        case .forest: return "纯白纸面 · 清透玻璃 · 柔和森林绿"
        case .classic: return "原有紫蓝配色 · 柔和圆角 · 轻透卡片"
        case .botanical: return "米绿纸面 · 圆润卡片 · 草木细线"
        case .editorial: return "书刊分栏 · 章节边注 · 暖纸墨线"
        case .coast: return "雾蓝背景 · 大圆角 · 轻盈白卡"
        case .rose: return "淡粉花笺 · 圆润字形 · 细边卡片"
        case .graphite: return "紧凑索引 · 等宽标注 · 利落边框"
        case .folio: return "双列藏书票 · 票根切口 · 竖向齿线"
        case .inkwash: return "山形留白 · 极简纸面 · 细墨线"
        case .blueprint: return "目录索引 · 坐标网格 · 双线边框"
        }
    }
    var accentHex: UInt32 {
        switch self { case .forest: return 0x3D6348; case .classic: return 0x594FDB; case .botanical: return 0x326953; case .editorial: return 0x77512C; case .coast: return 0x2B698A; case .rose: return 0x994C66; case .graphite: return 0x505664; case .folio: return 0x785239; case .inkwash: return 0x3E5A52; case .blueprint: return 0x285F93 }
    }
    var secondaryHex: UInt32 {
        switch self { case .forest: return 0x526458; case .classic: return 0x419BDC; case .botanical: return 0x8C784F; case .editorial: return 0x7B6260; case .coast: return 0x548C87; case .rose: return 0x8C7291; case .graphite: return 0x63778A; case .folio: return 0xA17A45; case .inkwash: return 0x768B7E; case .blueprint: return 0x477F99 }
    }
    var darkAccentHex: UInt32 {
        switch self { case .forest: return 0xBAD6C0; case .classic: return 0xB8B3FF; case .botanical: return 0x9ECAB4; case .editorial: return 0xDCC39D; case .coast: return 0x9BCCE5; case .rose: return 0xEAB1C6; case .graphite: return 0xC4CBD6; case .folio: return 0xE6C59B; case .inkwash: return 0xB6C8B9; case .blueprint: return 0xA4CFF2 }
    }
    var darkSecondaryHex: UInt32 {
        switch self { case .forest: return 0xAEBBB2; case .classic: return secondaryHex; case .botanical: return 0xD1C39C; case .editorial: return 0xD2B9B5; case .coast: return 0xA4CEC7; case .rose: return 0xCAB9D3; case .graphite: return 0xB5C8DC; case .folio: return 0xCFAF7B; case .inkwash: return 0xC4CEC6; case .blueprint: return 0xA6D5E5 }
    }
    var backgroundHex: UInt32 {
        switch self { case .forest: return 0xFFFFFF; case .classic: return 0xF2F2F7; case .botanical: return 0xEFF3EA; case .editorial: return 0xF3EFE6; case .coast: return 0xEDF4F8; case .rose: return 0xF8EFF1; case .graphite: return 0xECEDEF; case .folio: return 0xF1E9D9; case .inkwash: return 0xF1F2EC; case .blueprint: return 0xEAF1F7 }
    }
    var cardHex: UInt32 {
        switch self { case .forest: return 0xFFFFFF; case .classic: return 0xFFFFFF; case .botanical: return 0xFAFCF6; case .editorial: return 0xFFFCF6; case .coast: return 0xFBFDFF; case .rose: return 0xFFF9FA; case .graphite: return 0xFAFAFB; case .folio: return 0xFFFBF1; case .inkwash: return 0xFBFCF7; case .blueprint: return 0xF8FCFF }
    }
    var darkBackgroundHex: UInt32 {
        switch self { case .forest: return 0x151716; case .classic: return 0x000000; case .botanical: return 0x101B15; case .editorial: return 0x1B1813; case .coast: return 0x101C25; case .rose: return 0x23171E; case .graphite: return 0x141518; case .folio: return 0x201B14; case .inkwash: return 0x121B18; case .blueprint: return 0x101D2B }
    }
    var darkCardHex: UInt32 {
        switch self { case .forest: return 0x222423; case .classic: return 0x1C1C1E; case .botanical: return 0x1B2A21; case .editorial: return 0x2A261E; case .coast: return 0x1C2B36; case .rose: return 0x35252E; case .graphite: return 0x25272C; case .folio: return 0x30281E; case .inkwash: return 0x1E2A24; case .blueprint: return 0x192D40 }
    }
    var radius: CGFloat {
        switch self { case .forest: return 22; case .classic: return 18; case .botanical: return 20; case .editorial: return 6; case .coast: return 24; case .rose: return 22; case .graphite: return 10; case .folio: return 12; case .inkwash: return 4; case .blueprint: return 8 }
    }
    var usesNeutralGlass: Bool { self == .forest }
    var supportsLiveGlass: Bool { self == .forest || self == .classic }

    /// Circular controls keep their shape; content cards follow the chosen theme.
    func surfaceRadius(preferred: CGFloat?) -> CGFloat {
        guard let preferred else { return radius }
        if preferred >= 44 || supportsLiveGlass { return preferred }
        return min(preferred, radius)
    }

    var primaryInk: Color { usesNeutralGlass ? dynamicColor(light: 0x1C211D, dark: 0xF0F2EF) : .primary }
    // The suggested #858A85 is too light for small copy on white.
    var secondaryInk: Color { usesNeutralGlass ? dynamicColor(light: 0x626862, dark: 0xABB1AB) : .secondary }
    var selectionSurfaceHex: UInt32 { 0xF3F3F0 }
    var neutralBorderHex: UInt32 { 0xE6E8E3 }
    var controlFill: Color { dynamicColor(light: selectionSurfaceHex, dark: 0x303430) }
    var controlBorder: Color { dynamicColor(light: neutralBorderHex, dark: 0x414641) }

    var borderWidth: CGFloat { self == .editorial || self == .graphite || self == .blueprint ? 1 : 0.6 }
    var fontDesign: Font.Design {
        switch self { case .editorial, .folio, .inkwash: return .serif; case .graphite, .blueprint: return .monospaced; case .botanical, .rose: return .rounded; default: return .default }
    }
    var ornament: String {
        switch self { case .forest: return "leaf"; case .classic: return "book.closed"; case .botanical: return "leaf"; case .editorial: return "text.book.closed"; case .coast: return "water.waves"; case .rose: return "pencil.and.outline"; case .graphite: return "square.grid.3x3"; case .folio: return "ticket"; case .inkwash: return "mountain.2"; case .blueprint: return "ruler" }
    }
    func preferenceKey(_ component: String) -> String {
        self == .classic ? "settings.\(component)Hex" : "settings.visualTheme.\(rawValue).\(component)Hex"
    }
    func dynamicColor(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in Self.uiColor(traits.userInterfaceStyle == .dark ? dark : light) })
    }
    static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

/// Tiny vector brand mark: two leaves of paper and an open fold. No bitmap
/// decoding, rotating effects, blur, or per-frame geometry on Settings.
struct PaperBetweenMark: View {
    var size: CGFloat = 44

    var body: some View {
        let corner = size * (12.0 / 44.0)
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.accent,
                            Color(red: 0.22, green: 0.18, blue: 0.52)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                }
                .shadow(color: AppTheme.accent.opacity(0.28), radius: size * 0.16, x: 0, y: size * 0.08)

            ZStack {
                HStack(spacing: size * 0.03) {
                    RoundedRectangle(cornerRadius: size * 0.04, style: .continuous)
                        .fill(Color(white: 0.94))
                        .frame(width: size * 0.32, height: size * 0.44)
                        .rotationEffect(.degrees(-8))
                        .shadow(color: Color.black.opacity(0.15), radius: size * 0.04, x: -1, y: 2)

                    RoundedRectangle(cornerRadius: size * 0.04, style: .continuous)
                        .fill(Color.white)
                        .frame(width: size * 0.32, height: size * 0.44)
                        .rotationEffect(.degrees(8))
                        .shadow(color: Color.black.opacity(0.15), radius: size * 0.04, x: 1, y: 2)
                }

                Rectangle()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: size * 0.04, height: size * 0.40)

                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.98, green: 0.74, blue: 0.38), Color(red: 0.95, green: 0.58, blue: 0.25)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: size * 0.09, height: size * 0.50)
                }
                .offset(y: size * 0.06)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("纸间，书页之间")
    }
}
