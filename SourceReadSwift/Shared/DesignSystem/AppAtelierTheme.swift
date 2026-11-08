import SwiftUI

/// Reference pigments stay exact; text on the prominent colour field has its own ink.
struct AppAtelierPalette {
    let primaryHex: UInt32
    let secondaryHex: UInt32
    let emphasisFillHex: UInt32
    let emphasisInkHex: UInt32

    var primary: Color { Color(uiColor: AppVisualTheme.uiColor(primaryHex)) }
    var secondary: Color { Color(uiColor: AppVisualTheme.uiColor(secondaryHex)) }
    var emphasisFill: Color { Color(uiColor: AppVisualTheme.uiColor(emphasisFillHex)) }
    var emphasisInk: Color { Color(uiColor: AppVisualTheme.uiColor(emphasisInkHex)) }
}

extension AppVisualTheme {
    static let atelierThemes: [Self] = [.berryLake, .blushInk, .periwinkleCocoa, .peachMoss, .inkViolet, .pineMist, .kleinSage]
    var isAtelier: Bool { Self.atelierThemes.contains(self) }

    var atelierPalette: AppAtelierPalette? {
        switch self {
        case .berryLake:
            return .init(primaryHex: 0x65020A, secondaryHex: 0x18D5E7,
                         emphasisFillHex: 0x18D5E7, emphasisInkHex: 0x65020A)
        case .blushInk:
            return .init(primaryHex: 0xFF7CA2, secondaryHex: 0x000000,
                         emphasisFillHex: 0xFF7CA2, emphasisInkHex: 0x000000)
        case .periwinkleCocoa:
            return .init(primaryHex: 0x7B88D7, secondaryHex: 0x6D483B,
                         emphasisFillHex: 0x7B88D7, emphasisInkHex: 0x100B08)
        case .peachMoss:
            return .init(primaryHex: 0xFACBC6, secondaryHex: 0x465C47,
                         emphasisFillHex: 0xFACBC6, emphasisInkHex: 0x304131)
        case .inkViolet:
            // The reference purple needs a lighter field to survive the existing pressed opacity.
            return .init(primaryHex: 0x0B0C10, secondaryHex: 0xA855F7,
                         emphasisFillHex: 0xB873F8, emphasisInkHex: 0x0B0C10)
        case .pineMist:
            return .init(primaryHex: 0x3A6341, secondaryHex: 0xE8E8E4,
                         emphasisFillHex: 0xE8E8E4, emphasisInkHex: 0x29482F)
        case .kleinSage:
            return .init(primaryHex: 0x012696, secondaryHex: 0xA4E2C6,
                         emphasisFillHex: 0xA4E2C6, emphasisInkHex: 0x012696)
        default: return nil
        }
    }
}

