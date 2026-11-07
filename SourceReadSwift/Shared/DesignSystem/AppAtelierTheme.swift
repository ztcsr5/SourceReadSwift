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

/// Sparse, static print structures keep decoration away from readable content.
struct AppAtelierImprint: View {
    let theme: AppVisualTheme
    let isCard: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Canvas { context, size in
            guard let palette = theme.atelierPalette else { return }
            let primary = palette.primary
            let secondary = palette.secondary
            let opacity = contrast == .increased ? 1.0 : (isCard ? 0.90 : 0.65)
            switch theme {
            case .berryLake:
                let width: CGFloat = isCard ? 3 : 8
                context.fill(Path(CGRect(x: 0, y: 0, width: width, height: size.height * 0.58)), with: .color(primary.opacity(opacity)))
                context.fill(Path(CGRect(x: 0, y: size.height * 0.58, width: width, height: size.height * 0.42)), with: .color(secondary.opacity(opacity)))
            case .blushInk:
                var edge = Path()
                let x: CGFloat = isCard ? size.width - 7 : size.width - 12
                edge.move(to: CGPoint(x: x, y: 16))
                edge.addLine(to: CGPoint(x: x, y: size.height - 16))
                context.stroke(edge, with: .color(secondary.opacity(opacity)), lineWidth: 1)
                for y in stride(from: CGFloat(24), to: size.height - 16, by: 48) {
                    context.fill(Path(CGRect(x: x - 4, y: y, width: 4, height: 2)), with: .color(primary))
                }
            case .periwinkleCocoa:
                let diameter = min(size.width * (isCard ? 0.48 : 0.9), 360)
                let rect = CGRect(x: size.width - diameter * 0.55, y: -diameter * 0.48, width: diameter, height: diameter)
                context.stroke(Path(ellipseIn: rect), with: .color(primary.opacity(opacity * 0.25)), lineWidth: isCard ? 12 : 30)
                context.stroke(Path(ellipseIn: rect.insetBy(dx: 16, dy: 16)), with: .color(secondary.opacity(opacity * 0.5)), lineWidth: 1)
            case .peachMoss:
                guard isCard else { return }
                let frame = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
                context.stroke(Path(roundedRect: frame, cornerRadius: 11), with: .color(secondary.opacity(opacity)), lineWidth: 0.7)
                var line = Path()
                line.move(to: CGPoint(x: 18, y: size.height - 10))
                line.addLine(to: CGPoint(x: 48, y: size.height - 10))
                context.stroke(line, with: .color(primary), lineWidth: 2)
            case .inkViolet:
                let inset: CGFloat = isCard ? 6 : 12
                let length: CGFloat = isCard ? 12 : 24
                var corners = Path()
                corners.move(to: CGPoint(x: inset, y: inset + length))
                corners.addLine(to: CGPoint(x: inset, y: inset))
                corners.addLine(to: CGPoint(x: inset + length, y: inset))
                corners.move(to: CGPoint(x: size.width - inset - length, y: size.height - inset))
                corners.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
                corners.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset - length))
                context.stroke(corners, with: .color(secondary.opacity(opacity)), lineWidth: 1.5)
            case .pineMist:
                let edge: CGFloat = isCard ? 8 : 12
                for y in stride(from: CGFloat(24), to: size.height - 20, by: isCard ? 56 : 96) {
                    var needles = Path()
                    needles.move(to: CGPoint(x: size.width - edge - 5, y: y - 5))
                    needles.addLine(to: CGPoint(x: size.width - edge, y: y + 5))
                    needles.addLine(to: CGPoint(x: size.width - edge + 3, y: y - 3))
                    context.stroke(needles, with: .color(primary.opacity(opacity * 0.55)), lineWidth: 1)
                }
            case .kleinSage:
                let width = min(size.width * 0.28, 96)
                let inset: CGFloat = isCard ? 6 : 12
                context.fill(Path(CGRect(x: inset, y: inset, width: width, height: 3)), with: .color(primary))
                context.fill(Path(CGRect(x: size.width - width - inset, y: size.height - inset - 3,
                                         width: width, height: 3)), with: .color(secondary))
            default: break
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
