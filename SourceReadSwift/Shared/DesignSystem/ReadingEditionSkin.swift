import SwiftUI

/// Decorative vocabulary. It never owns navigation, gestures or preference writes.
enum ReadingEditionSkin: String, CaseIterable, Sendable {
    case ink, blade, bunny

    init?(theme: AppVisualTheme) {
        switch theme {
        case .shuimo: self = .ink
        case .wuxia: self = .blade
        case .kawaii: self = .bunny
        default: return nil
        }
    }

    var pressScale: CGFloat {
        switch self {
        case .ink: return 0.98
        case .blade: return 0.975
        case .bunny: return 0.955
        }
    }

    var contour: CGFloat {
        switch self {
        case .ink: return 7
        case .blade: return 10
        case .bunny: return 22
        }
    }

}

private struct ReadingEditionKey: EnvironmentKey {
    static let defaultValue: ReadingEditionSkin? = nil
}

extension EnvironmentValues {
    var readingEdition: ReadingEditionSkin? {
        get { self[ReadingEditionKey.self] }
        set { self[ReadingEditionKey.self] = newValue }
    }
}

struct EditionContour: Shape {
    let skin: ReadingEditionSkin

    func path(in rect: CGRect) -> Path {
        let radius = min(skin.contour, min(rect.width, rect.height) * 0.47)
        if skin != .blade {
            return Path(roundedRect: rect, cornerSize: CGSize(width: radius, height: radius))
        }
        // Chisel two opposed corners; the actual hit target stays rectangular.
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.closeSubpath()
        return path
    }
}

enum EditionControlRole: Equatable {
    case primary, secondary, quiet
}

struct EditionControlFinish: ViewModifier {
    let ink: Color
    let paper: Color
    var role: EditionControlRole = .secondary
    var isSelected = false
    var legacyRadius: CGFloat = 12
    var legacyFill: Color = .clear
    var legacyInk: Color = .primary
    @Environment(\.readingEdition) private var skin
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @AppMotion private var motion

    @ViewBuilder func body(content: Content) -> some View {
        if let skin {
            let isEmphasized = isEnabled && (role == .primary || isSelected)
            let shape = EditionContour(skin: skin)
            content
                .foregroundStyle(isEmphasized ? paper : ink)
                .background { shape.fill(isEmphasized ? ink : idleFill(skin)) }
                .overlay {
                    shape.insetStroke(ink.opacity(contrast == .increased ? 0.75 : idleStroke(skin)), width: 1)
                        .opacity(isEmphasized ? 0 : 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .overlay(alignment: .bottomTrailing) {
                    EditionEdgeMark(skin: skin, ink: isEmphasized ? paper : ink)
                        .frame(width: 16, height: 6)
                        .padding(.trailing, skin == .bunny ? 12 : 7)
                        .padding(.bottom, 3)
                        .opacity(isEmphasized ? 0.70 : 0)
                }
                .contentShape(Rectangle())
                .animation(motion.animation(.press), value: isSelected)
        } else {
            content.foregroundStyle(legacyInk)
                .background(legacyFill, in: RoundedRectangle(cornerRadius: legacyRadius, style: .continuous))
        }
    }

    private func idleFill(_ skin: ReadingEditionSkin) -> Color {
        guard role != .quiet else { return .clear }
        return ink.opacity(skin == .bunny ? 0.105 : 0.055)
    }

    private func idleStroke(_ skin: ReadingEditionSkin) -> Double {
        guard role != .quiet else { return 0 }
        return skin == .ink ? 0.30 : skin == .blade ? 0.40 : 0.20
    }
}

private extension EditionContour {
    func insetStroke(_ color: Color, width: CGFloat) -> some View {
        stroke(color, lineWidth: width).padding(width / 2)
    }
}

/// A small paper, brush or paw signature layered on top of (not in place of) system glass.
struct EditionPanelTrim: View {
    let ink: Color
    @Environment(\.readingEdition) private var skin
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        if let skin {
            EditionEdgeMark(skin: skin, ink: ink)
                .frame(width: skin == .blade ? 46 : 28, height: 9)
                .scaleEffect(x: layoutDirection == .rightToLeft ? -1 : 1)
                .padding(.trailing, 18)
                .padding(.bottom, 5)
                .opacity(0.66)
        }
    }
}

struct EditionEdgeMark: View {
    let skin: ReadingEditionSkin
    let ink: Color

    var body: some View {
        EdgePath(skin: skin).fill(ink)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    private struct EdgePath: Shape {
        let skin: ReadingEditionSkin

        func path(in rect: CGRect) -> Path {
            var stroke = Path()
            switch skin {
            case .ink:
                stroke.move(to: CGPoint(x: 0, y: 13))
                stroke.addQuadCurve(to: CGPoint(x: 100, y: 10), control: CGPoint(x: 34, y: -3))
                stroke.addQuadCurve(to: CGPoint(x: 0, y: 13), control: CGPoint(x: 53, y: 12))
                stroke.closeSubpath()
            case .blade:
                for points in [[(0, 17), (80, 3), (100, 0), (89, 7), (11, 19)],
                               [(20, 20), (88, 11), (96, 9), (82, 15), (20, 23)]] {
                    stroke.move(to: CGPoint(x: CGFloat(points[0].0), y: CGFloat(points[0].1)))
                    for point in points.dropFirst() { stroke.addLine(to: CGPoint(x: CGFloat(point.0), y: CGFloat(point.1))) }
                    stroke.closeSubpath()
                }
            case .bunny:
                stroke.addEllipse(in: CGRect(x: 33, y: 11, width: 34, height: 13))
                for x in [14, 42, 70] { stroke.addEllipse(in: CGRect(x: CGFloat(x), y: 1, width: 16, height: 7)) }
            }
            return stroke.applying(CGAffineTransform(a: rect.width / 100, b: 0, c: 0, d: rect.height / 24,
                                                     tx: rect.minX, ty: rect.minY))
        }
    }
}

struct EditionStatusDot: View {
    let isActive: Bool
    let ink: Color
    @Environment(\.readingEdition) private var skin
    @AppMotion private var motion

    var body: some View {
        if let skin {
            EditionEdgeMark(skin: skin, ink: ink)
                .frame(width: 13, height: 7)
                .padding(5)
                .opacity(isActive ? 1 : 0)
                .animation(motion.animation(.press), value: isActive)
        }
    }
}

struct EditionProgressRail: View {
    let fraction: Double
    let ink: Color
    @Environment(\.readingEdition) private var skin

    var body: some View {
        if let skin {
            GeometryReader { proxy in
                let width = proxy.size.width * CGFloat(min(max(fraction, 0), 1))
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.opacity(0.16)).frame(height: 2)
                    if width > 0 {
                        EditionContour(skin: skin).fill(ink).frame(width: width, height: skin == .bunny ? 6 : 4)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 6)
        } else {
            ProgressView(value: fraction).tint(ink)
        }
    }
}
