import SwiftUI

/// A recessed back plane, a lit shelf surface and a separate front edge.
struct ReadingDeskPlinth: View {
    let palette: FloatingDeskPalette
    let policy: FloatingDeskPolicy
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = ReadingPlinthOutline()
        glass(shape)
            .overlay {
                shape.fill(LinearGradient(stops: [
                    .init(color: palette.pearl.opacity(scheme == .dark ? 0.08 : 0.32), location: 0),
                    .init(color: palette.light.opacity(scheme == .dark ? 0.20 : 0.32), location: 0.27),
                    .init(color: palette.glassTint.opacity(0.18), location: 0.28),
                    .init(color: palette.shadow.opacity(scheme == .dark ? 0.12 : 0.07), location: 0.85),
                    .init(color: palette.light.opacity(0.36), location: 0.87),
                    .init(color: palette.pearl.opacity(0.52), location: 1)
                ], startPoint: .top, endPoint: .bottom))
            }
            .overlay(alignment: .top) {
                shape.strokeBorder(LinearGradient(colors: [
                    palette.pearl.opacity(scheme == .dark ? 0.30 : 0.88),
                    palette.light.opacity(0.20), palette.pearl.opacity(0.24)
                ], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: contrast == .increased ? 1.5 : 0.75)
            }
            .overlay(alignment: .bottom) {
                if policy.surface != .opaque {
                    Ellipse().fill(RadialGradient(colors: [
                        palette.shadow.opacity(scheme == .dark ? 0.66 : 0.40), .clear
                    ], center: .center, startRadius: 0, endRadius: 80))
                    .frame(width: 164, height: 8)
                    .padding(.bottom, 2)
                }
            }
            .shadow(color: palette.shadow.opacity(policy.surface == .opaque ? 0 : 0.09), radius: 3, y: 3)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder private func glass(_ shape: ReadingPlinthOutline) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), policy.surface == .liquidGlass {
            shape.fill(.clear).glassEffect(.regular.tint(palette.glassTint.opacity(0.24)), in: shape)
        } else { compatibleGlass(shape) }
        #else
        compatibleGlass(shape)
        #endif
    }

    @ViewBuilder private func compatibleGlass(_ shape: ReadingPlinthOutline) -> some View {
        if policy.surface == .opaque { shape.fill(palette.pearl) }
        else { shape.fill(.ultraThinMaterial).overlay { shape.fill(palette.glassTint.opacity(0.18)) } }
    }
}

/// Drawn in front of the jacket, rather than painted into its background.
struct ReadingDeskFrontEdge: View {
    let palette: FloatingDeskPalette
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(palette.pearl.opacity(scheme == .dark ? 0.28 : 0.88)).frame(height: 0.75)
            LinearGradient(colors: [palette.light.opacity(0.42), palette.glassTint.opacity(0.72)],
                startPoint: .top, endPoint: .bottom)
            Rectangle().fill(palette.shadow.opacity(scheme == .dark ? 0.36 : 0.16)).frame(height: 0.75)
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ReadingPlinthOutline: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in bounds: CGRect) -> Path {
        let rect = bounds.insetBy(dx: insetAmount, dy: insetAmount)
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let top = min(max(12 - insetAmount, 0), min(rect.width, rect.height) / 2)
        let bottom = min(max(4 - insetAmount, 0), min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + top),
            control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - bottom, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bottom),
            control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}
