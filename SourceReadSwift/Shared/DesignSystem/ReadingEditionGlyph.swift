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

/// Reuses the edition's stamp on actual shelf and reader section headings, not only the theme preview.
struct EditionHeadingLabel: View {
    let title: String
    let font: Font
    let ink: Color
    var isCompact = false
    @Environment(\.readingEdition) private var skin

    var body: some View {
        if let skin {
            HStack(spacing: isCompact ? 6 : 8) {
                let side: CGFloat = isCompact ? 20 : 30
                EditionSigil(skin: skin, ink: ink)
                    .frame(width: side * 0.62, height: side * 0.62)
                    .frame(width: side, height: side)
                    .background(EditionContour(skin: skin).fill(ink.opacity(0.08)))
                    .overlay {
                        EditionContour(skin: skin).stroke(ink.opacity(0.28), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                    .accessibilityHidden(true)
                Text(title).font(font)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(title).font(font)
        }
    }
}

struct EditionGlyphPath: Shape {
    enum Kind: Equatable {
        case read, bookmark, bookmarked, index, filter, grid, sort, check, sigil
        case back, forward, close, highlight, speak, pause, play, swap, search, add, subtract, more, sun, moon
    }
    let skin: ReadingEditionSkin
    let glyph: Kind

    static func kind(for systemName: String) -> Kind? {
        switch systemName {
        case "book", "book.closed", "book.pages", "book.badge.plus", "textformat.size": return .read
        case "bookmark": return .bookmark
        case "bookmark.fill": return .bookmarked
        case "list.bullet", "text.alignleft", "rectangle.grid.1x2": return .index
        case "line.3.horizontal.decrease.circle", "line.3.horizontal.decrease.circle.fill", "slider.horizontal.3":
            return .filter
        case "square.grid.2x2": return .grid
        case "arrow.up.arrow.down": return .sort
        case "checkmark", "checkmark.circle.fill": return .check
        case "paintpalette", "sparkles.rectangle.stack", "gearshape", "books.vertical": return .sigil
        case "chevron.left", "arrow.left": return .back
        case "chevron.right", "arrow.right": return .forward
        case "xmark", "xmark.circle", "xmark.circle.fill": return .close
        case "highlighter": return .highlight
        case "speaker.wave.2", "speaker.wave.3.fill", "headphones": return .speak
        case "pause.fill", "pause.circle.fill": return .pause
        case "play.fill", "play.circle.fill": return .play
        case "arrow.triangle.2.circlepath": return .swap
        case "magnifyingglass": return .search
        case "plus", "plus.circle.fill": return .add
        case "minus", "minus.circle.fill": return .subtract
        case "ellipsis", "ellipsis.circle": return .more
        case "sun.max", "sun.max.fill": return .sun
        case "moon", "moon.stars": return .moon
        case "arrow.up.and.down.text.horizontal": return .index
        case "rectangle.portrait.and.arrow.right": return .forward
        case "square.stack": return .grid
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
        case .filter: path = filter()
        case .grid: path = grid()
        case .sort: path = sort()
        case .check: path = check()
        case .sigil: path = sigil()
        case .back: path = chevronArrow(isBack: true)
        case .forward: path = chevronArrow(isBack: false)
        case .close: path = closeMark()
        case .highlight: path = highlightBrush()
        case .speak: path = speakWave()
        case .pause: path = pauseMark()
        case .play: path = playMark()
        case .swap: path = swapArcs()
        case .search: path = searchLens()
        case .add: path = plusMinus(isPlus: true)
        case .subtract: path = plusMinus(isPlus: false)
        case .more: path = moreDots()
        case .sun: path = sunMark()
        case .moon: path = moonMark()
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

    private func filter() -> Path {
        var path = Path()
        path.move(to: pt(3, 5)); path.addLine(to: pt(21, 5))
        path.addLine(to: pt(14, 13)); path.addLine(to: pt(14, 17.5))
        path.addLine(to: pt(10, 20)); path.addLine(to: pt(10, 13))
        path.closeSubpath()
        return path
    }

    private func grid() -> Path {
        var path = Path()
        for column in [CGFloat(3), 13] {
            for row in [CGFloat(3), 13] {
                let rect = CGRect(x: column, y: row, width: 8, height: 8)
                path.addPath(EditionContour(skin: skin).path(in: rect))
            }
        }
        return path
    }

    private func sort() -> Path {
        var path = Path()
        path.move(to: pt(7, 20)); path.addLine(to: pt(7, 4))
        path.move(to: pt(3, 8)); path.addLine(to: pt(7, 4)); path.addLine(to: pt(11, 8))
        path.move(to: pt(17, 4)); path.addLine(to: pt(17, 20))
        path.move(to: pt(13, 16)); path.addLine(to: pt(17, 20)); path.addLine(to: pt(21, 16))
        if skin == .bunny { path.addEllipse(in: CGRect(x: 10, y: 10, width: 4, height: 4)) }
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
        case .sky:
            var path = Path()
            path.move(to: pt(12, 2))
            path.addQuadCurve(to: pt(22, 12), control: pt(13.7, 10.3))
            path.addQuadCurve(to: pt(12, 22), control: pt(13.7, 13.7))
            path.addQuadCurve(to: pt(2, 12), control: pt(10.3, 13.7))
            path.addQuadCurve(to: pt(12, 2), control: pt(10.3, 10.3))
            path.closeSubpath()
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

    private func chevronArrow(isBack: Bool) -> Path {
        var path = Path()
        switch skin {
        case .blade:
            // Angular barbed spearhead + sword-guard stem.
            if isBack {
                path.move(to: pt(14.5, 4.5)); path.addLine(to: pt(5.5, 12)); path.addLine(to: pt(14.5, 19.5))
                path.move(to: pt(6.5, 12)); path.addLine(to: pt(18.5, 12))
                path.move(to: pt(16, 9)); path.addLine(to: pt(16, 15))
            } else {
                path.move(to: pt(9.5, 4.5)); path.addLine(to: pt(18.5, 12)); path.addLine(to: pt(9.5, 19.5))
                path.move(to: pt(5.5, 12)); path.addLine(to: pt(17.5, 12))
                path.move(to: pt(8, 9)); path.addLine(to: pt(8, 15))
            }
        case .ink:
            // Calligraphic brush hook stroke.
            if isBack {
                path.move(to: pt(15.5, 5))
                path.addQuadCurve(to: pt(7, 12), control: pt(12, 9.5))
                path.addQuadCurve(to: pt(16, 19.5), control: pt(10, 16))
            } else {
                path.move(to: pt(8.5, 5))
                path.addQuadCurve(to: pt(17, 12), control: pt(12, 9.5))
                path.addQuadCurve(to: pt(8, 19.5), control: pt(14, 16))
            }
        case .bunny:
            // Plump rounded chevron with tiny bead tip.
            if isBack {
                path.move(to: pt(15, 5.5))
                path.addQuadCurve(to: pt(7.5, 12), control: pt(9.5, 9))
                path.addQuadCurve(to: pt(15, 18.5), control: pt(9.5, 15))
                path.addEllipse(in: CGRect(x: 16.5, y: 11, width: 2, height: 2))
            } else {
                path.move(to: pt(9, 5.5))
                path.addQuadCurve(to: pt(16.5, 12), control: pt(14.5, 9))
                path.addQuadCurve(to: pt(9, 18.5), control: pt(14.5, 15))
                path.addEllipse(in: CGRect(x: 5.5, y: 11, width: 2, height: 2))
            }
        case .sky:
            let x1: CGFloat = isBack ? 15 : 9
            let x2: CGFloat = isBack ? 7.5 : 16.5
            path.move(to: pt(x1, 5)); path.addLine(to: pt(x2, 12)); path.addLine(to: pt(x1, 19))
        }
        return path
    }

    private func closeMark() -> Path {
        var path = Path()
        switch skin {
        case .blade:
            // Crossed blades + angular hilt notches.
            path.move(to: pt(5, 5)); path.addLine(to: pt(19, 19))
            path.move(to: pt(19, 5)); path.addLine(to: pt(5, 19))
            path.move(to: pt(4.5, 8)); path.addLine(to: pt(8, 4.5))
            path.move(to: pt(16, 19.5)); path.addLine(to: pt(19.5, 16))
        case .ink:
            // Open square seal corners + X brush cross.
            path.move(to: pt(7, 7)); path.addLine(to: pt(17, 17))
            path.move(to: pt(17, 7)); path.addLine(to: pt(7, 17))
            path.move(to: pt(3.5, 8)); path.addLine(to: pt(3.5, 3.5)); path.addLine(to: pt(8, 3.5))
            path.move(to: pt(16, 20.5)); path.addLine(to: pt(20.5, 20.5)); path.addLine(to: pt(20.5, 16))
        case .bunny:
            // Cute ribbon bow cross + center knot dot.
            path.move(to: pt(6.5, 6.5)); path.addQuadCurve(to: pt(17.5, 17.5), control: pt(13, 11))
            path.move(to: pt(17.5, 6.5)); path.addQuadCurve(to: pt(6.5, 17.5), control: pt(11, 11))
            path.addEllipse(in: CGRect(x: 10.6, y: 10.6, width: 2.8, height: 2.8))
        case .sky:
            path.move(to: pt(6, 6)); path.addLine(to: pt(18, 18))
            path.move(to: pt(18, 6)); path.addLine(to: pt(6, 18))
        }
        return path
    }

    private func highlightBrush() -> Path {
        var path = Path()
        // Pointed blade knife / calligraphy brush / cute marker + sparkle depending on skin.
        path.move(to: pt(15.5, 3.5)); path.addLine(to: pt(20.5, 8.5))
        path.addLine(to: pt(9.5, 19.5)); path.addLine(to: pt(4, 20.5))
        path.addLine(to: pt(5, 15)); path.closeSubpath()
        if skin == .blade {
            path.move(to: pt(12, 7)); path.addLine(to: pt(17, 12))
            path.move(to: pt(11, 21)); path.addLine(to: pt(20.5, 21))
        } else if skin == .bunny {
            path.addEllipse(in: CGRect(x: 5.5, y: 4.5, width: 3, height: 3))
            path.move(to: pt(10, 21)); path.addQuadCurve(to: pt(20, 20.5), control: pt(15, 22))
        } else {
            path.move(to: pt(6.5, 14.5)); path.addLine(to: pt(10, 18))
            path.move(to: pt(10, 21)); path.addLine(to: pt(20, 21))
        }
        return path
    }

    private func speakWave() -> Path {
        var path = Path()
        if skin == .blade {
            path.move(to: pt(4, 9.5)); path.addLine(to: pt(8, 9.5)); path.addLine(to: pt(13, 4.5))
            path.addLine(to: pt(13, 19.5)); path.addLine(to: pt(8, 14.5)); path.addLine(to: pt(4, 14.5)); path.closeSubpath()
            path.move(to: pt(16.5, 8)); path.addLine(to: pt(18.5, 12)); path.addLine(to: pt(16.5, 16))
            path.move(to: pt(19.5, 5.5)); path.addLine(to: pt(22, 12)); path.addLine(to: pt(19.5, 18.5))
        } else {
            path.move(to: pt(4.5, 9.5)); path.addLine(to: pt(8.5, 9.5)); path.addLine(to: pt(13, 5))
            path.addLine(to: pt(13, 19)); path.addLine(to: pt(8.5, 14.5)); path.addLine(to: pt(4.5, 14.5)); path.closeSubpath()
            path.move(to: pt(16, 9)); path.addQuadCurve(to: pt(16, 15), control: pt(18.5, 12))
            path.move(to: pt(18.8, 6.5)); path.addQuadCurve(to: pt(18.8, 17.5), control: pt(22, 12))
        }
        return path
    }

    private func pauseMark() -> Path {
        var path = Path()
        let corner: CGFloat = skin == .bunny ? 2 : skin == .blade ? 0 : 1
        path.addRoundedRect(in: CGRect(x: 6.5, y: 5, width: 3.8, height: 14), cornerSize: CGSize(width: corner, height: corner))
        path.addRoundedRect(in: CGRect(x: 13.7, y: 5, width: 3.8, height: 14), cornerSize: CGSize(width: corner, height: corner))
        return path
    }

    private func playMark() -> Path {
        var path = Path()
        if skin == .bunny {
            path.move(to: pt(7.5, 5.5))
            path.addQuadCurve(to: pt(18.5, 12), control: pt(13.5, 7))
            path.addQuadCurve(to: pt(7.5, 18.5), control: pt(13.5, 17))
            path.closeSubpath()
        } else {
            path.move(to: pt(7, 4.5)); path.addLine(to: pt(19.5, 12)); path.addLine(to: pt(7, 19.5)); path.closeSubpath()
            if skin == .blade {
                path.move(to: pt(5, 7.5)); path.addLine(to: pt(5, 16.5))
            }
        }
        return path
    }

    private func swapArcs() -> Path {
        var path = Path()
        path.addArc(center: pt(12, 12), radius: 7.5, startAngle: .degrees(-150), endAngle: .degrees(-20), clockwise: false)
        path.move(to: pt(16.8, 6.8)); path.addLine(to: pt(19.5, 9.5)); path.addLine(to: pt(15.5, 10.2))
        path.addArc(center: pt(12, 12), radius: 7.5, startAngle: .degrees(30), endAngle: .degrees(160), clockwise: false)
        path.move(to: pt(7.2, 17.2)); path.addLine(to: pt(4.5, 14.5)); path.addLine(to: pt(8.5, 13.8))
        return path
    }

    private func searchLens() -> Path {
        var path = Path()
        if skin == .blade {
            // Octagonal bronze mirror lens.
            path.addPath(EditionContour(skin: .blade).path(in: CGRect(x: 4, y: 4, width: 12, height: 12)))
            path.move(to: pt(14.5, 14.5)); path.addLine(to: pt(20.5, 20.5))
        } else {
            path.addEllipse(in: CGRect(x: 4.5, y: 4.5, width: 11.5, height: 11.5))
            path.move(to: pt(14.4, 14.4)); path.addLine(to: pt(20, 20))
            if skin == .bunny {
                path.addEllipse(in: CGRect(x: 8.5, y: 7.5, width: 2.2, height: 2.2))
            }
        }
        return path
    }

    private func plusMinus(isPlus: Bool) -> Path {
        var path = Path()
        path.move(to: pt(5.5, 12)); path.addLine(to: pt(18.5, 12))
        if isPlus {
            path.move(to: pt(12, 5.5)); path.addLine(to: pt(12, 18.5))
        }
        if skin == .blade {
            path.move(to: pt(4, 10)); path.addLine(to: pt(4, 14))
            path.move(to: pt(20, 10)); path.addLine(to: pt(20, 14))
        }
        return path
    }

    private func moreDots() -> Path {
        var path = Path()
        if skin == .blade {
            // Three sharp diamond sparks.
            for cx in [CGFloat(5.5), 12.0, 18.5] {
                path.move(to: pt(cx, 10)); path.addLine(to: pt(cx + 2, 12))
                path.addLine(to: pt(cx, 14)); path.addLine(to: pt(cx - 2, 12)); path.closeSubpath()
            }
        } else if skin == .bunny {
            // Three playful beads (middle popped higher).
            path.addEllipse(in: CGRect(x: 4, y: 11.2, width: 2.6, height: 2.6))
            path.addEllipse(in: CGRect(x: 10.7, y: 9.8, width: 2.8, height: 2.8))
            path.addEllipse(in: CGRect(x: 17.4, y: 11.2, width: 2.6, height: 2.6))
        } else {
            for cx in [CGFloat(5.5), 12.0, 18.5] {
                path.addEllipse(in: CGRect(x: cx - 1.3, y: 10.7, width: 2.6, height: 2.6))
            }
        }
        return path
    }

    private func sunMark() -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 7.5, y: 7.5, width: 9, height: 9))
        for deg in stride(from: 0.0, to: 360.0, by: 45.0) {
            let rad = deg * .pi / 180.0
            let r1: CGFloat = 6.2
            let r2: CGFloat = 9.0
            path.move(to: pt(12 + cos(rad) * r1, 12 + sin(rad) * r1))
            path.addLine(to: pt(12 + cos(rad) * r2, 12 + sin(rad) * r2))
        }
        return path
    }

    private func moonMark() -> Path {
        var path = Path()
        path.addArc(center: pt(12, 12), radius: 7.5, startAngle: .degrees(-60), endAngle: .degrees(135), clockwise: false)
        path.addQuadCurve(to: pt(15.6, 5.6), control: pt(11.5, 13.5))
        if skin == .bunny || skin == .sky {
            path.move(to: pt(17.5, 6.5)); path.addLine(to: pt(17.5, 9.5))
            path.move(to: pt(16, 8)); path.addLine(to: pt(19, 8))
        }
        return path
    }

    private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
}
