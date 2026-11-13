import SwiftUI

/// Reference pigments stay exact; text on the prominent colour field has its own ink.
struct AppAtelierPalette {
    let primaryHex: UInt32
    let secondaryHex: UInt32
    let emphasisFillHex: UInt32
    let emphasisInkHex: UInt32
    /// 深色下要换成提亮的同一色相：浅色填充压在深色卡片上会失去 3:1 边界。
    let darkEmphasisFillHex: UInt32
    let darkEmphasisInkHex: UInt32

    var primary: Color { Color(uiColor: AppVisualTheme.uiColor(primaryHex)) }
    var secondary: Color { Color(uiColor: AppVisualTheme.uiColor(secondaryHex)) }
    var emphasisFill: Color {
        Color(uiColor: UIColor { traits in
            AppVisualTheme.uiColor(traits.userInterfaceStyle == .dark ? darkEmphasisFillHex : emphasisFillHex)
        })
    }
    var emphasisInk: Color {
        Color(uiColor: UIColor { traits in
            AppVisualTheme.uiColor(traits.userInterfaceStyle == .dark ? darkEmphasisInkHex : emphasisInkHex)
        })
    }
}

extension AppVisualTheme {
    static let atelierThemes: [Self] = [.berryLake, .blushInk, .periwinkleCocoa, .peachMoss, .inkViolet, .pineMist, .kleinSage]
    var isAtelier: Bool { Self.atelierThemes.contains(self) }

    var atelierPalette: AppAtelierPalette? {
        switch self {
        case .berryLake:
            return .init(primaryHex: 0x7A0A1E, secondaryHex: 0x0F7C8C,
                         emphasisFillHex: 0x0A5761, emphasisInkHex: 0xFFFFFF,
                         darkEmphasisFillHex: 0x7FE0EC, darkEmphasisInkHex: 0x06222A)
        case .blushInk:
            return .init(primaryHex: 0xAE2253, secondaryHex: 0x1F5041,
                         emphasisFillHex: 0x173C31, emphasisInkHex: 0xFFFFFF,
                         darkEmphasisFillHex: 0x9EE0C6, darkEmphasisInkHex: 0x0A2419)
        case .periwinkleCocoa:
            return .init(primaryHex: 0x39459B, secondaryHex: 0x6D483B,
                         emphasisFillHex: 0x6D483B, emphasisInkHex: 0xFFF6EE,
                         darkEmphasisFillHex: 0xE6C4AE, darkEmphasisInkHex: 0x2A1B12)
        case .peachMoss:
            return .init(primaryHex: 0x8A4A3C, secondaryHex: 0x2F5C3A,
                         emphasisFillHex: 0x2F5C3A, emphasisInkHex: 0xFFF2EE,
                         darkEmphasisFillHex: 0xB4E8C4, darkEmphasisInkHex: 0x12301B)
        case .inkViolet:
            // Violet and ochre sit ~133° apart on the wheel; pressed opacity still keeps 5.5:1.
            return .init(primaryHex: 0x4A1D7A, secondaryHex: 0x8A6100,
                         emphasisFillHex: 0x6E4C00, emphasisInkHex: 0xFFFFFF,
                         darkEmphasisFillHex: 0xFFD97A, darkEmphasisInkHex: 0x2A1D00)
        case .pineMist:
            return .init(primaryHex: 0x1F4A32, secondaryHex: 0x9E5B4A,
                         emphasisFillHex: 0x6E3B2E, emphasisInkHex: 0xFFFFFF,
                         darkEmphasisFillHex: 0xF2C4AE, darkEmphasisInkHex: 0x2C1710)
        case .kleinSage:
            return .init(primaryHex: 0x012696, secondaryHex: 0x855A0C,
                         emphasisFillHex: 0x6B4700, emphasisInkHex: 0xFFFFFF,
                         darkEmphasisFillHex: 0xFFD97A, darkEmphasisInkHex: 0x2A1D00)
        default: return nil
        }
    }
}

