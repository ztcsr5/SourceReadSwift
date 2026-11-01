import SwiftUI
import UIKit

/// A coordinated visual language, not a synonym for an accent colour.
enum AppVisualTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case classic, botanical, editorial, coast, rose, graphite
    var id: String { rawValue }
    static var current: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: "settings.visualTheme") ?? "") ?? .classic
    }
    var title: String {
        switch self {
        case .classic: return "纸间 · 原初"
        case .botanical: return "草木书房"
        case .editorial: return "书刊编辑室"
        case .coast: return "海岸来信"
        case .rose: return "花笺手记"
        case .graphite: return "石墨工作台"
        }
    }
    var detail: String {
        switch self {
        case .classic: return "原有紫蓝配色 · 柔和圆角 · 轻透卡片"
        case .botanical: return "米绿纸面 · 圆润卡片 · 草木细线"
        case .editorial: return "暖白书刊 · 衬线正文 · 小圆角墨线"
        case .coast: return "雾蓝背景 · 大圆角 · 轻盈白卡"
        case .rose: return "淡粉花笺 · 圆润字形 · 细边卡片"
        case .graphite: return "中性灰阶 · 等宽正文 · 利落边框"
        }
    }
    var accentHex: UInt32 {
        switch self { case .classic: return 0x594FDB; case .botanical: return 0x326953; case .editorial: return 0x77512C; case .coast: return 0x2B698A; case .rose: return 0x994C66; case .graphite: return 0x505664 }
    }
    var secondaryHex: UInt32 {
        switch self { case .classic: return 0x419BDC; case .botanical: return 0x8C784F; case .editorial: return 0x7B6260; case .coast: return 0x548C87; case .rose: return 0x8C7291; case .graphite: return 0x63778A }
    }
    var backgroundHex: UInt32 {
        switch self { case .classic: return 0xF2F2F7; case .botanical: return 0xEFF3EA; case .editorial: return 0xF3EFE6; case .coast: return 0xEDF4F8; case .rose: return 0xF8EFF1; case .graphite: return 0xECEDEF }
    }
    var cardHex: UInt32 {
        switch self { case .classic: return 0xFFFFFF; case .botanical: return 0xFAFCF6; case .editorial: return 0xFFFCF6; case .coast: return 0xFBFDFF; case .rose: return 0xFFF9FA; case .graphite: return 0xFAFAFB }
    }
    var darkBackgroundHex: UInt32 {
        switch self { case .classic: return 0x000000; case .botanical: return 0x101B15; case .editorial: return 0x1B1813; case .coast: return 0x101C25; case .rose: return 0x23171E; case .graphite: return 0x141518 }
    }
    var darkCardHex: UInt32 {
        switch self { case .classic: return 0x1C1C1E; case .botanical: return 0x1B2A21; case .editorial: return 0x2A261E; case .coast: return 0x1C2B36; case .rose: return 0x35252E; case .graphite: return 0x25272C }
    }
    var radius: CGFloat {
        switch self { case .classic: return 18; case .botanical: return 20; case .editorial: return 6; case .coast: return 24; case .rose: return 22; case .graphite: return 10 }
    }
    var borderWidth: CGFloat { self == .editorial || self == .graphite ? 1 : 0.6 }
    var fontDesign: Font.Design {
        switch self { case .editorial: return .serif; case .graphite: return .monospaced; case .botanical, .rose: return .rounded; default: return .default }
    }
    var ornament: String {
        switch self { case .classic: return "book.closed"; case .botanical: return "leaf"; case .editorial: return "text.book.closed"; case .coast: return "water.waves"; case .rose: return "pencil.and.outline"; case .graphite: return "square.grid.3x3" }
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
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(AppTheme.accent.opacity(0.10))
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2).fill(AppTheme.accent)
                    .frame(width: 9, height: 23).rotationEffect(.degrees(-12))
                RoundedRectangle(cornerRadius: 2).fill(AppTheme.secondaryAccent)
                    .frame(width: 9, height: 23).rotationEffect(.degrees(12))
            }
            Rectangle().fill(AppTheme.card).frame(width: 1.5, height: 17).offset(y: 3)
        }
        .frame(width: 40, height: 44)
        .accessibilityLabel("纸间，书页之间")
    }
}
