import SwiftUI

/// Static vector structures, not bitmap wallpaper or a per-frame animation layer.
struct AppThemeOrnament: View {
    let theme: AppVisualTheme
    var isCard = false

    static func hasArtwork(theme: AppVisualTheme, isCard: Bool) -> Bool {
        if theme.isAtelier { return theme != .peachMoss || isCard }
        switch theme {
        case .folio, .blueprint: return true
        case .inkwash: return !isCard
        default: return false
        }
    }

    @ViewBuilder var body: some View {
        if theme.isAtelier && Self.hasArtwork(theme: theme, isCard: isCard) {
            AppAtelierImprint(theme: theme, isCard: isCard)
        } else if Self.hasArtwork(theme: theme, isCard: isCard) {
            artwork
        }
    }

    private var artwork: some View {
        Canvas { context, size in
            let ink = theme.dynamicColor(light: theme.accentHex, dark: theme.darkAccentHex)
            var path = Path()
            switch theme {
            case .folio:
                let x: CGFloat = isCard ? 14 : 24
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(ink.opacity(isCard ? 0.18 : 0.08)), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            case .inkwash:
                guard !isCard else { return }
                path.move(to: CGPoint(x: 0, y: size.height * 0.30))
                path.addQuadCurve(to: CGPoint(x: size.width, y: size.height * 0.20), control: CGPoint(x: size.width * 0.40, y: -40))
                path.addLine(to: CGPoint(x: size.width, y: 0)); path.addLine(to: .zero); path.closeSubpath()
                context.fill(path, with: .color(ink.opacity(0.045)))
            case .blueprint:
                let step: CGFloat = isCard ? 24 : 32
                for x in stride(from: CGFloat(0), to: size.width, by: step) {
                    path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: CGFloat(0), to: size.height, by: step) {
                    path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(ink.opacity(isCard ? 0.035 : 0.06)), lineWidth: 0.5)
                if isCard { context.stroke(Path(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 5, dy: 5), cornerRadius: 4), with: .color(ink.opacity(0.14)), lineWidth: 0.5) }
            default: break
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct AppThemeCardShape: Shape {
    let theme: AppVisualTheme
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        if theme == .berryLake, radius < 44 {
            let cut: CGFloat = min(12, min(rect.width, rect.height) / 4)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
        guard theme == .folio else { return Path(roundedRect: rect, cornerRadius: radius) }
        var path = Path(roundedRect: rect, cornerRadius: radius)
        for x in [rect.minX, rect.maxX] {
            path.addEllipse(in: CGRect(x: x - 6, y: rect.midY - 6, width: 12, height: 12))
        }
        return path
    }
}
