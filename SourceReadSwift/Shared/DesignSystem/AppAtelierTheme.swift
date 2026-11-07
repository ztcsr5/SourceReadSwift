import SwiftUI

extension AppVisualTheme {
    static let atelierThemes: [Self] = [.berryLake, .blushInk, .periwinkleCocoa, .peachMoss]
    var isAtelier: Bool { Self.atelierThemes.contains(self) }
}

/// Sparse, static print structures keep decoration away from readable content.
struct AppAtelierImprint: View {
    let theme: AppVisualTheme
    let isCard: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Canvas { context, size in
            let primary = theme.dynamicColor(light: theme.accentHex, dark: theme.darkAccentHex)
            let secondary = theme.dynamicColor(light: theme.secondaryHex, dark: theme.darkSecondaryHex)
            let opacity = contrast == .increased ? 0.30 : (isCard ? 0.18 : 0.07)
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
                    context.fill(Path(CGRect(x: x - 4, y: y, width: 4, height: 2)), with: .color(primary.opacity(opacity * 2)))
                }
            case .periwinkleCocoa:
                let diameter = min(size.width * (isCard ? 0.48 : 0.9), 360)
                let rect = CGRect(x: size.width - diameter * 0.55, y: -diameter * 0.48, width: diameter, height: diameter)
                context.stroke(Path(ellipseIn: rect), with: .color(primary.opacity(opacity)), lineWidth: isCard ? 12 : 30)
                context.stroke(Path(ellipseIn: rect.insetBy(dx: 16, dy: 16)), with: .color(secondary.opacity(opacity)), lineWidth: 1)
            case .peachMoss:
                guard isCard else { return }
                let frame = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
                context.stroke(Path(roundedRect: frame, cornerRadius: 11), with: .color(secondary.opacity(opacity)), lineWidth: 0.7)
                var line = Path()
                line.move(to: CGPoint(x: 18, y: size.height - 10))
                line.addLine(to: CGPoint(x: 48, y: size.height - 10))
                context.stroke(line, with: .color(primary.opacity(opacity * 2)), lineWidth: 2)
            default: break
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
