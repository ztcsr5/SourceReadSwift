import SwiftUI

/// Horizontal divider stylized for the active ReadingEditionSkin.
struct EditionDivider: View {
    var ink: Color = AppTheme.accent
    var verticalPadding: CGFloat = 4
    @Environment(\.readingEdition) private var skin

    var body: some View {
        Group {
            if let skin {
                Canvas { context, size in
                    drawDivider(in: &context, size: size, skin: skin)
                }
                .frame(height: skin == .bunny ? 12 : 10)
                .padding(.vertical, verticalPadding)
                .accessibilityHidden(true)
            } else {
                Divider()
            }
        }
    }

    private func drawDivider(in context: inout GraphicsContext, size: CGSize, skin: ReadingEditionSkin) {
        let midY = size.height * 0.5
        let w = size.width
        guard w > 12 else { return }

        switch skin {
        case .blade:
            // Split dry-brush sword-wind stroke with center diamond guard.
            let leftEnd = w * 0.44
            let rightStart = w * 0.56
            var slash = Path()
            slash.move(to: CGPoint(x: 0, y: midY + 1.0))
            slash.addLine(to: CGPoint(x: leftEnd, y: midY - 1.1))
            slash.addLine(to: CGPoint(x: leftEnd - 2, y: midY + 0.8))
            slash.closeSubpath()
            context.fill(slash, with: .color(ink.opacity(0.62)))

            var tail = Path()
            tail.move(to: CGPoint(x: rightStart + 2, y: midY - 0.9))
            tail.addLine(to: CGPoint(x: w, y: midY + 0.4))
            tail.addLine(to: CGPoint(x: rightStart, y: midY + 0.9))
            tail.closeSubpath()
            context.fill(tail, with: .color(ink.opacity(0.54)))

            // Dry-brush whisker lines.
            var whisker = Path()
            whisker.move(to: CGPoint(x: 8, y: midY - 2.3))
            whisker.addLine(to: CGPoint(x: w * 0.34, y: midY - 1.8))
            whisker.move(to: CGPoint(x: w * 0.66, y: midY + 2.1))
            whisker.addLine(to: CGPoint(x: w - 6, y: midY + 1.5))
            context.stroke(whisker, with: .color(ink.opacity(0.24)), lineWidth: 0.8)

            // Center diamond guard.
            let cx = w * 0.5
            var diamond = Path()
            diamond.move(to: CGPoint(x: cx, y: midY - 4.0))
            diamond.addLine(to: CGPoint(x: cx + 4.4, y: midY))
            diamond.addLine(to: CGPoint(x: cx, y: midY + 4.0))
            diamond.addLine(to: CGPoint(x: cx - 4.4, y: midY))
            diamond.closeSubpath()
            context.fill(diamond, with: .color(ink.opacity(0.78)))

        case .ink:
            // Flowing monochrome sumi-e horizon with seal center dot.
            var wave = Path()
            wave.move(to: CGPoint(x: 0, y: midY + 0.4))
            wave.addCurve(
                to: CGPoint(x: w * 0.44, y: midY),
                control1: CGPoint(x: w * 0.14, y: midY - 2.0),
                control2: CGPoint(x: w * 0.30, y: midY + 1.8)
            )
            wave.move(to: CGPoint(x: w * 0.56, y: midY))
            wave.addCurve(
                to: CGPoint(x: w, y: midY - 0.3),
                control1: CGPoint(x: w * 0.72, y: midY - 1.8),
                control2: CGPoint(x: w * 0.88, y: midY + 1.6)
            )
            context.stroke(
                wave,
                with: .color(ink.opacity(0.38)),
                style: StrokeStyle(lineWidth: 1.3, lineCap: .round)
            )

            // Center square seal glyph.
            let sealRect = CGRect(x: w * 0.5 - 3.5, y: midY - 3.5, width: 7, height: 7)
            context.stroke(Path(roundedRect: sealRect, cornerRadius: 1.5), with: .color(ink.opacity(0.65)), lineWidth: 1.1)
            context.fill(Path(ellipseIn: sealRect.insetBy(dx: 2.0, dy: 2.0)), with: .color(ink.opacity(0.55)))

        case .bunny:
            // Hand-stitched pastel ribbon with centered mini bunny-ear emblem.
            var stitch = Path()
            stitch.move(to: CGPoint(x: 0, y: midY))
            stitch.addLine(to: CGPoint(x: w * 0.43, y: midY))
            stitch.move(to: CGPoint(x: w * 0.57, y: midY))
            stitch.addLine(to: CGPoint(x: w, y: midY))
            context.stroke(
                stitch,
                with: .color(ink.opacity(0.36)),
                style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [4, 4])
            )

            // Cute centered bunny ears & round face.
            let cx = w * 0.5
            var leftEar = Path(ellipseIn: CGRect(x: cx - 3.6, y: midY - 5.4, width: 2.5, height: 4.8))
            let rightEar = Path(ellipseIn: CGRect(x: cx + 1.1, y: midY - 5.4, width: 2.5, height: 4.8))
            leftEar.addPath(rightEar)
            context.fill(leftEar, with: .color(ink.opacity(0.70)))
            let head = Path(ellipseIn: CGRect(x: cx - 4.0, y: midY - 1.2, width: 8.0, height: 6.0))
            context.fill(head, with: .color(ink.opacity(0.75)))

        case .sky:
            // Crisp hairline rule with 4-point star sparkle.
            var line = Path()
            line.move(to: CGPoint(x: 0, y: midY))
            line.addLine(to: CGPoint(x: w * 0.45, y: midY))
            line.move(to: CGPoint(x: w * 0.55, y: midY))
            line.addLine(to: CGPoint(x: w, y: midY))
            context.stroke(line, with: .color(ink.opacity(0.28)), lineWidth: 1)

            let cx = w * 0.5
            var star = Path()
            let rOut: CGFloat = 4.5
            let rIn: CGFloat = 1.4
            star.move(to: CGPoint(x: cx, y: midY - rOut))
            star.addLine(to: CGPoint(x: cx + rIn, y: midY - rIn))
            star.addLine(to: CGPoint(x: cx + rOut, y: midY))
            star.addLine(to: CGPoint(x: cx + rIn, y: midY + rIn))
            star.addLine(to: CGPoint(x: cx, y: midY + rOut))
            star.addLine(to: CGPoint(x: cx - rIn, y: midY + rIn))
            star.addLine(to: CGPoint(x: cx - rOut, y: midY))
            star.addLine(to: CGPoint(x: cx - rIn, y: midY - rIn))
            star.closeSubpath()
            context.fill(star, with: .color(ink.opacity(0.72)))
        }
    }
}

/// Decorative corner notches/accents aligned with the active edition skin.
struct EditionCornerTrim: View {
    let skin: ReadingEditionSkin
    let ink: Color
    var inset: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            guard w > 24, h > 24 else { return }

            switch skin {
            case .blade:
                // Opposite sword-guard corner ticks matching bevel orientation.
                var brackets = Path()
                let len: CGFloat = 10
                // Top-right crisp L
                brackets.move(to: CGPoint(x: w - inset - len, y: inset))
                brackets.addLine(to: CGPoint(x: w - inset, y: inset))
                brackets.addLine(to: CGPoint(x: w - inset, y: inset + len))
                // Bottom-left crisp L
                brackets.move(to: CGPoint(x: inset + len, y: h - inset))
                brackets.addLine(to: CGPoint(x: inset, y: h - inset))
                brackets.addLine(to: CGPoint(x: inset, y: h - inset - len))
                context.stroke(
                    brackets,
                    with: .color(ink.opacity(0.45)),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .square, lineJoin: .miter)
                )

            case .ink:
                // Classical Song-edition bookplate inner corner ticks.
                var ticks = Path()
                let arm: CGFloat = 9
                // Top-left & bottom-right corner seals
                ticks.move(to: CGPoint(x: inset, y: inset + arm))
                ticks.addLine(to: CGPoint(x: inset, y: inset))
                ticks.addLine(to: CGPoint(x: inset + arm, y: inset))
                ticks.move(to: CGPoint(x: w - inset - arm, y: h - inset))
                ticks.addLine(to: CGPoint(x: w - inset, y: h - inset))
                ticks.addLine(to: CGPoint(x: w - inset, y: h - inset - arm))
                context.stroke(
                    ticks,
                    with: .color(ink.opacity(0.40)),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .square)
                )

            case .bunny:
                // Subtle pastel dots & mini bunny-ear pin at top-trailing corner.
                let px = w - inset - 8
                let py = inset + 7
                let ear1 = Path(ellipseIn: CGRect(x: px - 3.2, y: py - 5.2, width: 2.3, height: 5.0))
                let ear2 = Path(ellipseIn: CGRect(x: px + 0.8, y: py - 5.2, width: 2.3, height: 5.0))
                let face = Path(ellipseIn: CGRect(x: px - 3.6, y: py - 1.2, width: 7.2, height: 5.4))
                context.fill(ear1, with: .color(ink.opacity(0.38)))
                context.fill(ear2, with: .color(ink.opacity(0.38)))
                context.fill(face, with: .color(ink.opacity(0.42)))

            case .sky:
                // 4-point star sparkle near top-trailing corner.
                let cx = w - inset - 6
                let cy = inset + 6
                var star = Path()
                star.move(to: CGPoint(x: cx, y: cy - 4))
                star.addLine(to: CGPoint(x: cx + 1.2, y: cy - 1.2))
                star.addLine(to: CGPoint(x: cx + 4, y: cy))
                star.addLine(to: CGPoint(x: cx + 1.2, y: cy + 1.2))
                star.addLine(to: CGPoint(x: cx, y: cy + 4))
                star.addLine(to: CGPoint(x: cx - 1.2, y: cy + 1.2))
                star.addLine(to: CGPoint(x: cx - 4, y: cy))
                star.addLine(to: CGPoint(x: cx - 1.2, y: cy - 1.2))
                star.closeSubpath()
                context.fill(star, with: .color(ink.opacity(0.46)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Interactive slider styled per active ReadingEditionSkin; falls back cleanly to system Slider when nil.
struct EditionSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var ink: Color = AppTheme.accent
    var paper: Color = AppTheme.card
    var onEditingChanged: (Bool) -> Void = { _ in }

    @Environment(\.readingEdition) private var skin
    @State private var isDragging = false

    private var normalized: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (value - range.lowerBound) / span))
    }

    var body: some View {
        if let skin {
            GeometryReader { proxy in
                let trackWidth = max(1, proxy.size.width - 24)
                let thumbX = 12 + trackWidth * normalized

                ZStack(alignment: .leading) {
                    trackLayer(skin: skin, width: proxy.size.width, thumbX: thumbX)
                    thumbView(skin: skin)
                        .scaleEffect(isDragging ? 1.14 : 1.0)
                        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.72), value: isDragging)
                        .position(x: thumbX, y: proxy.size.height * 0.5)
                }
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if !isDragging {
                                isDragging = true
                                onEditingChanged(true)
                            }
                            let ratio = min(1, max(0, (gesture.location.x - 12) / trackWidth))
                            let raw = range.lowerBound + (range.upperBound - range.lowerBound) * ratio
                            let next = snappedValue(raw)
                            if next != value {
                                value = next
                            }
                        }
                        .onEnded { _ in
                            if isDragging {
                                isDragging = false
                                onEditingChanged(false)
                            }
                        }
                )
            }
            .frame(height: 34)
            .accessibilityRepresentation {
                if let step, step > 0 {
                    Slider(value: $value, in: range, step: step, onEditingChanged: onEditingChanged)
                } else {
                    Slider(value: $value, in: range, onEditingChanged: onEditingChanged)
                }
            }
        } else if let step, step > 0 {
            Slider(value: $value, in: range, step: step, onEditingChanged: onEditingChanged)
                .tint(ink)
        } else {
            Slider(value: $value, in: range, onEditingChanged: onEditingChanged)
                .tint(ink)
        }
    }

    private func snappedValue(_ raw: Double) -> Double {
        let clamped = min(range.upperBound, max(range.lowerBound, raw))
        guard let step, step > 0 else { return clamped }
        let offset = ((clamped - range.lowerBound) / step).rounded() * step
        return min(range.upperBound, max(range.lowerBound, range.lowerBound + offset))
    }

    @ViewBuilder
    private func trackLayer(skin: ReadingEditionSkin, width: CGFloat, thumbX: CGFloat) -> some View {
        let filled = max(0, min(width, thumbX))
        switch skin {
        case .blade:
            // Stark angular sword-qi track.
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(ink.opacity(0.18))
                    .frame(height: 4)
                    .overlay(Rectangle().stroke(ink.opacity(0.32), lineWidth: 0.7))
                Rectangle()
                    .fill(ink.opacity(0.92))
                    .frame(width: filled, height: 5)
            }
            .padding(.horizontal, 12)

        case .ink:
            // Xuan-paper ink-flow stream track with subtle outer line.
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(ink.opacity(0.14))
                    .frame(height: 5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(ink.opacity(0.28), lineWidth: 0.8)
                    )
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(ink.opacity(0.84))
                    .frame(width: max(0, filled - 8), height: 5)
            }
            .padding(.horizontal, 12)

        case .bunny:
            // Pastel stitched ribbon track.
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ink.opacity(0.14))
                    .frame(height: 7)
                    .overlay(
                        Capsule()
                            .stroke(ink.opacity(0.26), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    )
                Capsule()
                    .fill(ink.opacity(0.82))
                    .frame(width: max(6, filled - 4), height: 7)
            }
            .padding(.horizontal, 12)

        case .sky:
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ink.opacity(0.16))
                    .frame(height: 5)
                Capsule()
                    .fill(ink.opacity(0.88))
                    .frame(width: max(4, filled - 8), height: 5)
            }
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private func thumbView(skin: ReadingEditionSkin) -> some View {
        switch skin {
        case .blade:
            // Diamond sword-guard thumb with central vertical slit.
            ZStack {
                DiamondShape()
                    .fill(paper)
                    .frame(width: 20, height: 20)
                    .overlay(DiamondShape().stroke(ink, lineWidth: 2.0))
                Rectangle()
                    .fill(ink)
                    .frame(width: 2, height: 8)
            }
            .shadow(color: ink.opacity(0.28), radius: 0, x: 1.5, y: 1.5)

        case .ink:
            // Rectangular carved inkstone seal thumb.
            ZStack {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(paper)
                    .frame(width: 17, height: 21)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .stroke(ink, lineWidth: 1.8)
                    )
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(ink.opacity(0.85))
                    .frame(width: 3, height: 9)
            }
            .shadow(color: .black.opacity(0.16), radius: 2, y: 1)

        case .bunny:
            // Perky bunny-head badge thumb with two bunny ears and cute nose dot.
            ZStack {
                HStack(spacing: 4) {
                    Capsule()
                        .fill(paper)
                        .frame(width: 5, height: 10)
                        .overlay(Capsule().stroke(ink, lineWidth: 1.4))
                    Capsule()
                        .fill(paper)
                        .frame(width: 5, height: 10)
                        .overlay(Capsule().stroke(ink, lineWidth: 1.4))
                }
                .offset(y: -8)

                Circle()
                    .fill(paper)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(ink, lineWidth: 1.8))

                VStack(spacing: 2) {
                    HStack(spacing: 4.5) {
                        Circle().fill(ink).frame(width: 2.2, height: 2.2)
                        Circle().fill(ink).frame(width: 2.2, height: 2.2)
                    }
                    Circle().fill(ink.opacity(0.88)).frame(width: 3, height: 2.5)
                }
                .offset(y: 0.5)
            }
            .shadow(color: ink.opacity(0.24), radius: 3, y: 1.5)

        case .sky:
            // Clean cel-shaded 4-point star circle thumb.
            ZStack {
                Circle()
                    .fill(paper)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(ink, lineWidth: 1.8))
                Circle()
                    .fill(ink)
                    .frame(width: 7, height: 7)
            }
        }
    }
}

private struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// Custom ToggleStyle activated when an active ReadingEditionSkin exists.
struct EditionToggleStyle: ToggleStyle {
    let skin: ReadingEditionSkin
    var ink: Color = AppTheme.accent
    var paper: Color = AppTheme.card

    func makeBody(configuration: Configuration) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.78)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                configuration.label
                Spacer(minLength: 8)
                switchTrack(isOn: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }

    @ViewBuilder
    private func switchTrack(isOn: Bool) -> some View {
        let trackShape = EditionContour(skin: skin)
        let activeFill = isOn ? ink : ink.opacity(0.11)
        let strokeColor = isOn ? ink : ink.opacity(skin == .blade ? 0.45 : 0.30)

        ZStack(alignment: isOn ? .trailing : .leading) {
            trackShape
                .fill(activeFill)
                .frame(width: 48, height: 27)
                .overlay {
                    trackShape.stroke(
                        strokeColor,
                        style: skin == .bunny && !isOn
                            ? StrokeStyle(lineWidth: 1.4, dash: [3.5, 2.5])
                            : StrokeStyle(lineWidth: skin == .blade ? 1.5 : 1.1)
                    )
                }

            switchThumb(isOn: isOn)
                .padding(.horizontal, 3.5)
        }
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.76), value: isOn)
    }

    @ViewBuilder
    private func switchThumb(isOn: Bool) -> some View {
        let thumbFill = paper
        let detailColor = ink

        switch skin {
        case .blade:
            // Faceted blade-bevel toggle block.
            ZStack {
                EditionContour(skin: .blade)
                    .fill(thumbFill)
                    .frame(width: 21, height: 20)
                    .overlay(EditionContour(skin: .blade).stroke(detailColor, lineWidth: isOn ? 0 : 1.3))
                Rectangle()
                    .fill(detailColor)
                    .frame(width: 2, height: 8)
            }

        case .ink:
            // Square Xuan seal toggle block.
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(thumbFill)
                    .frame(width: 20, height: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(detailColor, lineWidth: isOn ? 0 : 1.1)
                    )
                Circle()
                    .fill(detailColor.opacity(isOn ? 0.85 : 0.48))
                    .frame(width: 5, height: 5)
            }

        case .bunny:
            // Cute miniature bunny silhouette contained within the track height.
            ZStack {
                HStack(spacing: 2.5) {
                    Capsule()
                        .fill(thumbFill)
                        .frame(width: 3.4, height: 6.8)
                        .overlay(Capsule().stroke(detailColor.opacity(isOn ? 0.2 : 0.45), lineWidth: 0.9))
                    Capsule()
                        .fill(thumbFill)
                        .frame(width: 3.4, height: 6.8)
                        .overlay(Capsule().stroke(detailColor.opacity(isOn ? 0.2 : 0.45), lineWidth: 0.9))
                }
                .offset(y: -5.5)
                Circle()
                    .fill(thumbFill)
                    .frame(width: 15, height: 15)
                    .overlay(Circle().stroke(detailColor.opacity(isOn ? 0.15 : 0.50), lineWidth: 1.1))
                    .offset(y: 2)
                Circle()
                    .fill(detailColor.opacity(isOn ? 0.85 : 0.45))
                    .frame(width: 3.5, height: 3.5)
                    .offset(y: 2.5)
            }
            .frame(width: 20, height: 22)

        case .sky:
            ZStack {
                Circle()
                    .fill(thumbFill)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(detailColor.opacity(isOn ? 0.15 : 0.45), lineWidth: 1.2))
                DiamondShape()
                    .fill(detailColor)
                    .frame(width: 7, height: 7)
            }
        }
    }
}

/// Applies EditionToggleStyle automatically when an edition skin is active, leaving core themes on system toggle.
struct EditionToggleModifier: ViewModifier {
    var ink: Color = AppTheme.accent
    var paper: Color = AppTheme.card
    @Environment(\.readingEdition) private var skin

    @ViewBuilder
    func body(content: Content) -> some View {
        if let skin {
            content.toggleStyle(EditionToggleStyle(skin: skin, ink: ink, paper: paper))
        } else {
            content
        }
    }
}

extension View {
    func editionToggleStyle(ink: Color = AppTheme.accent, paper: Color = AppTheme.card) -> some View {
        modifier(EditionToggleModifier(ink: ink, paper: paper))
    }
}
