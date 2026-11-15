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
        if let skin = ReadingEditionSkin(theme: theme) {
            EditionEdgeMark(skin: skin, ink: theme.dynamicColor(light: theme.secondaryHex, dark: theme.darkSecondaryHex))
                .frame(width: skin == .blade ? 38 : 24, height: 7)
                .padding(.trailing, 12)
                .padding(.bottom, 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isCard ? .bottomTrailing : .topTrailing)
                .opacity(isCard ? 0.68 : 0.38)
                .allowsHitTesting(false)
        } else if theme == .inkwash && !isCard {
            artwork
        }
    }

    private var artwork: some View {
        Canvas { context, size in
            let ink = theme.dynamicColor(light: theme.accentHex, dark: theme.darkAccentHex)
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
