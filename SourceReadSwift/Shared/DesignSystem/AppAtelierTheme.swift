import SwiftUI

/// Reference pigments stay exact; text on the prominent colour field has its own ink.
struct AppAtelierPalette {
    let primaryHex: UInt32
    let secondaryHex: UInt32
    let darkPrimaryHex: UInt32
    let darkSecondaryHex: UInt32
    let emphasisFillHex: UInt32
    let emphasisInkHex: UInt32
    /// 深色下换成提亮的同一色相：浅色填充压在深色卡片上会失去 3:1 边界。
    let darkEmphasisFillHex: UInt32
    let darkEmphasisInkHex: UInt32

    var primary: Color {
        Color(uiColor: UIColor { traits in
            AppVisualTheme.uiColor(traits.userInterfaceStyle == .dark ? darkPrimaryHex : primaryHex)
        })
    }

    var secondary: Color {
        Color(uiColor: UIColor { traits in
            AppVisualTheme.uiColor(traits.userInterfaceStyle == .dark ? darkSecondaryHex : secondaryHex)
        })
    }

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
    static let atelierThemes: [Self] = [.kleinSage]
    var isAtelier: Bool { Self.atelierThemes.contains(self) }

    var atelierPalette: AppAtelierPalette? {
        switch self {
        case .kleinSage:
            return .init(
                primaryHex: 0x012696,
                secondaryHex: 0x855A0C,
                darkPrimaryHex: 0x9DB4FF,
                darkSecondaryHex: 0xFFD97A,
                emphasisFillHex: 0x6B4700,
                emphasisInkHex: 0xFFFFFF,
                darkEmphasisFillHex: 0xFFD97A,
                darkEmphasisInkHex: 0x2A1D00
            )
        default:
            return nil
        }
    }
}
