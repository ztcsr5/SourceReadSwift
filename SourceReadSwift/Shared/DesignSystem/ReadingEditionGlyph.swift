import SwiftUI

/// Change icon drawing, not its VoiceOver label or the native button interaction.
struct EditionGlyph: View {
    let systemName: String
    var size: CGFloat = 17
    var weight: Font.Weight = .semibold
    @Environment(\.readingEdition) private var skin

    var body: some View {
        if let skin, let glyph = EditionGlyphPath.kind(for: systemName) {
            EditionGlyphPath(skin: skin, glyph: glyph)
                .stroke(.foreground, style: StrokeStyle(
                    lineWidth: skin == .blade ? 1.55 : skin == .bunny ? 1.65 : 1.35,
                    lineCap: skin == .blade ? .square : .round,
                    lineJoin: skin == .blade ? .miter : .round
                ))
                .frame(width: size + 3, height: size + 3)
                .accessibilityHidden(true)
        } else {
            Image(systemName: systemName)
                .font(.system(size: size, weight: weight))
                .accessibilityHidden(true)
        }
    }
}

struct EditionActionLabel: View {
    let title: String
    let systemImage: String
    @Environment(\.readingEdition) private var skin

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        if skin != nil {
            Label {
                Text(title)
            } icon: {
                EditionGlyph(systemName: systemImage)
            }
        } else {
            Label(title, systemImage: systemImage)
        }
    }
}

struct EditionSigil: View {
    let skin: ReadingEditionSkin
    let ink: Color

    var body: some View {
        EditionGlyphPath(skin: skin, glyph: .sigil)
            .stroke(ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

struct EditionGlyphPath: Shape {
    enum Kind: Equatable { case read, bookmark, bookmarked, index, check, sigil }
    let skin: ReadingEditionSkin
    let glyph: Kind

    static func kind(for systemName: String) -> Kind? {
        switch systemName {
        case "book", "book.closed", "book.pages", "book.badge.plus", "textformat.size": return .read
        case "bookmark": return .bookmark
        case "bookmark.fill": return .bookmarked
        case "list.bullet", "text.alignleft", "line.3.horizontal.decrease.circle",
             "line.3.horizontal.decrease.circle.fill": return .index
        case "checkmark", "checkmark.circle.fill": return .check
        case "paintpalette", "sparkles.rectangle.stack", "gearshape", "books.vertical": return .sigil
        default: return nil
        }
    }

    /// Unit art drawn as paths; no symbol morph, animation timer or offscreen blur.
    func path(in rect: CGRect) -> Path {
        let path: Path
        switch glyph {
        case .read: path = openBook()
        case .bookmark, .bookmarked: path = bookmark(isMarked: glyph == .bookmarked)
        case .index: path = index()
        case .check: path = check()
        case .sigil: path = sigil()
        }
        return path.applying(CGAffineTransform(a: rect.width / 24, b: 0, c: 0, d: rect.height / 24,
                                              tx: rect.minX, ty: rect.minY))
    }

    private func openBook() -> Path {
        var path = Path()
        let arc: CGFloat = skin == .bunny ? 3 : skin == .blade ? 0 : 1.5
        path.move(to: pt(12, 6))
        path.addQuadCurve(to: pt(2.5, 5), control: pt(6, 3 - arc / 3))
        path.addLine(to: pt(2.5, 17.5))
        path.addQuadCurve(to: pt(12, 19), control: pt(6, 16 - arc / 3))
        path.addQuadCurve(to: pt(21.5, 17.5), control: pt(18, 16 - arc / 3))
        path.addLine(to: pt(21.5, 5))
        path.addQuadCurve(to: pt(12, 6), control: pt(18, 3 - arc / 3))
        path.addLine(to: pt(12, 19))
        path.move(to: pt(6, 9)); path.addLine(to: pt(9, 9.7))
        path.move(to: pt(15, 9.7)); path.addLine(to: pt(18, 9))
        return path
    }

    private func bookmark(isMarked: Bool) -> Path {
        var path = Path()
        path.move(to: pt(6, 3)); path.addLine(to: pt(18, 3)); path.addLine(to: pt(18, 21))
        let peak: CGFloat = skin == .blade ? 9.5 : 12
        path.addLine(to: pt(peak, skin == .bunny ? 17 : 15))
        path.addLine(to: pt(6, 21)); path.closeSubpath()
        if isMarked {
            path.move(to: pt(8.5, 9)); path.addLine(to: pt(11, 11.5)); path.addLine(to: pt(15.5, 7))
        }
        return path
    }

    private func index() -> Path {
        var path = Path()
        for y in [CGFloat(6), 12, 18] {
            if skin == .bunny {
                path.addEllipse(in: CGRect(x: 2.5, y: y - 0.65, width: 1.3, height: 1.3))
            } else {
                path.move(to: pt(2, y + 0.7)); path.addLine(to: pt(5, y - 0.7))
            }
            path.move(to: pt(8, y)); path.addLine(to: pt(y == 18 ? 17 : 21, y))
        }
        return path
    }

    private func check() -> Path {
        var path = Path()
        if skin != .blade { path.addEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20)) }
        path.move(to: pt(6.7, 12.1)); path.addLine(to: pt(10.1, 15.1)); path.addLine(to: pt(17.8, 7.9))
        return path
    }

    private func sigil() -> Path {
        switch skin {
        case .ink:
            var path = Path()
            path.addArc(center: pt(12, 12), radius: 9, startAngle: .degrees(20), endAngle: .degrees(320), clockwise: false)
            path.move(to: pt(4.5, 16))
            path.addQuadCurve(to: pt(11, 8), control: pt(8.4, 11.6))
            path.addQuadCurve(to: pt(19.3, 15.3), control: pt(15, 13.2))
            return path
        case .blade:
            var path = Path()
            path.move(to: pt(3, 20)); path.addLine(to: pt(18, 3)); path.addLine(to: pt(22, 2))
            path.addLine(to: pt(19, 8)); path.addLine(to: pt(5, 21)); path.closeSubpath()
            path.move(to: pt(5, 14)); path.addLine(to: pt(10, 19))
            return path
        case .bunny:
            return bunny()
        }
    }

    private func bunny() -> Path {
        var path = Path()
        path.move(to: pt(7.7, 10))
        path.addCurve(to: pt(7, 3.1), control1: pt(4.4, 7.2), control2: pt(4.2, 3.2))
        path.addQuadCurve(to: pt(11.4, 9.1), control: pt(10.1, 2.9))
        path.addQuadCurve(to: pt(14.4, 9.4), control: pt(13, 8.7))
        path.addQuadCurve(to: pt(19.5, 3.9), control: pt(16.4, 2.8))
        path.addQuadCurve(to: pt(18.2, 11.3), control: pt(21.5, 5.4))
        path.addCurve(to: pt(11.8, 21), control1: pt(23.8, 18.3), control2: pt(17.5, 21.7))
        path.addCurve(to: pt(7.7, 10), control1: pt(4, 20.5), control2: pt(2.1, 14.5))
        path.closeSubpath()
        path.move(to: pt(8.5, 15)); path.addLine(to: pt(8.5, 15.6))
        path.move(to: pt(15.5, 15)); path.addLine(to: pt(15.5, 15.6))
        path.move(to: pt(11.2, 17.2)); path.addQuadCurve(to: pt(12.8, 17.2), control: pt(12, 18.4))
        return path
    }

    private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
}
