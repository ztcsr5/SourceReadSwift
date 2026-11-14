import SwiftUI

/// Static vector structures, not bitmap wallpaper or a per-frame animation layer.
struct AppThemeOrnament: View {
    let theme: AppVisualTheme
    var isCard = false

    static func hasArtwork(theme: AppVisualTheme, isCard: Bool) -> Bool {
        if theme.isAtelier { return false }
        if theme == .forest { return false }
        switch theme {
        case .inkwash: return !isCard
        case .shuimo, .wuxia, .kawaii: return true
        default: return false
        }
    }

    @ViewBuilder var body: some View {
        if Self.hasArtwork(theme: theme, isCard: isCard) {
            artwork
        }
    }

    private var artwork: some View {
        Canvas { context, size in
            let ink = theme.dynamicColor(light: theme.accentHex, dark: theme.darkAccentHex)
            let secondary = theme.dynamicColor(light: theme.secondaryHex, dark: theme.darkSecondaryHex)
            var path = Path()
            switch theme {
            case .inkwash:
                guard !isCard else { return }
                path.move(to: CGPoint(x: 0, y: size.height * 0.30))
                path.addQuadCurve(to: CGPoint(x: size.width, y: size.height * 0.20),
                                  control: CGPoint(x: size.width * 0.40, y: -40))
                path.addLine(to: CGPoint(x: size.width, y: 0))
                path.addLine(to: .zero)
                path.closeSubpath()
                context.fill(path, with: .color(ink.opacity(0.045)))
            case .shuimo:
                if isCard {
                    // Subtle cinnabar corner stamp accent on cards
                    let stampRect = CGRect(x: size.width - 14, y: 10, width: 4, height: 12)
                    context.fill(Path(roundedRect: stampRect, cornerRadius: 1.5),
                                 with: .color(secondary.opacity(0.55)))
                } else {
                    let inset = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
                    context.stroke(Path(roundedRect: inset, cornerRadius: 8),
                                   with: .color(ink.opacity(0.06)), lineWidth: 0.75)
                }
            case .wuxia:
                if isCard {
                    path.move(to: CGPoint(x: 12, y: size.height - 8))
                    path.addLine(to: CGPoint(x: min(size.width - 12, 86), y: size.height - 8))
                    context.stroke(path, with: .color(secondary.opacity(0.45)), lineWidth: 1)
                } else {
                    path.move(to: CGPoint(x: 0, y: 88))
                    path.addLine(to: CGPoint(x: size.width, y: 74))
                    context.stroke(path, with: .color(secondary.opacity(0.08)), lineWidth: 0.8)
                }
            case .kawaii:
                if isCard {
                    // Static scalloped washi corner tape hint
                    path.move(to: CGPoint(x: 14, y: 2))
                    path.addLine(to: CGPoint(x: 34, y: 2))
                    context.stroke(path, with: .color(secondary.opacity(0.45)), style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                }
            default:
                break
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct AppThemeCardShape: Shape {
    let theme: AppVisualTheme
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: radius)
    }
}
