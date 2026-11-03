import SwiftUI

/// A complete book floats across one shallow glass plane; metadata stays outside the glass.
struct FloatingReadingDesk: View {
    let book: BookshelfBook
    var heroNamespace: Namespace.ID? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @Environment(\.isFloatingDeskPressed) private var isPressed
    @AppStorage("settings.visualTheme") private var themeRaw = AppVisualTheme.classic.rawValue
    @AppStorage("settings.appearanceRevision") private var appearanceRevision = 0
    @AppMotion private var motion
    @ScaledMetric(relativeTo: .title2) private var titleRowHeight: CGFloat = 32
    @ScaledMetric(relativeTo: .title2) private var titleFontSize: CGFloat = 24
    @State private var conservesEnergy = ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState.rawValue >= 2
    @State private var coverImage: UIImage?
    @State private var tone: CoverTone?

    private var theme: AppVisualTheme { AppVisualTheme(rawValue: themeRaw) ?? .classic }
    private var palette: FloatingDeskPalette {
        let _ = appearanceRevision
        return .resolve(theme: theme)
    }
    private var policy: FloatingDeskPolicy {
        .resolve(.init(reducesMotion: motion.reducesMotion, reducesTransparency: reducesTransparency,
                 increasedContrast: contrast == .increased, conservesEnergy: conservesEnergy),
                 hasLiquidGlass: AppThemeSurfaceStyle.nativeGlassAvailable)
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let width: CGFloat = geometry.size.width < 310 ? 136 : 144
                let height: CGFloat = geometry.size.width < 310 ? 188 : 196
                ZStack(alignment: .top) {
                    environment.frame(height: 220)
                        .modifier(FloatingDeskParallax(depth: 3 * palette.finish.parallaxStrength, reducesDepth: policy.reducesDepth))
                    stage.frame(height: 124).padding(.top, 86)
                        .modifier(FloatingDeskParallax(depth: 7 * palette.finish.parallaxStrength, reducesDepth: policy.reducesDepth))
                    if !typeSize.isAccessibilitySize {
                        makeMarginNotes(coverWidth: width).padding(.top, 122)
                            .modifier(FloatingDeskParallax(depth: 30 * palette.finish.parallaxStrength, reducesDepth: policy.reducesDepth))
                    }
                    jacket(width: width, height: height).frame(maxWidth: .infinity)
                        .modifier(FloatingDeskParallax(depth: 22 * palette.finish.parallaxStrength, reducesDepth: policy.reducesDepth))
                }
            }.frame(height: 220)
            caption
                .modifier(FloatingDeskParallax(depth: 34 * palette.finish.parallaxStrength, reducesDepth: policy.reducesDepth))
        }
        .foregroundStyle(palette.ink)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("轻点打开书籍详情，长按管理")
        .task(id: coverImage.map(ObjectIdentifier.init)) {
            guard let coverImage else { tone = nil; return }
            let sampled = await CoverToneSampler.shared.tone(for: coverImage)
            guard !Task.isCancelled else { return }
            // Never resample during a drag. New palettes enter only when a cached/downsampled cover arrives.
            withAnimation(policy.reducesDepth ? nil : motion.animation(.background)) { tone = sampled }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in updateEnergyPolicy() }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in updateEnergyPolicy() }
    }

    private var environment: some View {
        ZStack {
            if contrast != .increased {
                RadialGradient(colors: [palette.light.opacity(scheme == .dark ? 0.22 : 0.34), .clear],
                    center: UnitPoint(x: 0.5, y: 0.62), startRadius: 4, endRadius: 180)
                RadialGradient(colors: [pigment.opacity(0.08), .clear],
                    center: UnitPoint(x: 0.28, y: 0.4), startRadius: 0, endRadius: 140)
            }
        }.opacity(palette.finish.environmentStrength).allowsHitTesting(false)
    }

    private var pigment: Color {
        tone.map { Color(red: $0.vividRed, green: $0.vividGreen, blue: $0.vividBlue) } ?? palette.mist
    }

    private var stage: some View {
        ZStack {
            glassPlane
            if contrast != .increased {
                LinearGradient(colors: [palette.pearl.opacity(0.45), .clear, palette.light.opacity(0.14)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Ellipse().fill(RadialGradient(colors: [palette.shadow.opacity(scheme == .dark ? 0.32 : 0.19), .clear],
                    center: .center, startRadius: 0, endRadius: 84))
                    .frame(width: 170, height: 18).offset(x: -3, y: 51)
            }
        }.overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.ink.opacity(0.45), lineWidth: 1.5)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [palette.pearl.opacity(0.85), palette.mist.opacity(0.10), palette.pearl.opacity(0.28)],
                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
            }
        }
        .shadow(color: palette.shadow.opacity(contrast == .increased ? 0 : 0.06), radius: 12, y: 8)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var glassPlane: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), policy.surface == .liquidGlass {
            shape.fill(.clear).glassEffect(.regular.tint(palette.glassTint.opacity(palette.finish.glassTintOpacity)), in: shape)
        } else { compatiblePlane(shape) }
        #else
        compatiblePlane(shape)
        #endif
    }

    @ViewBuilder private func compatiblePlane(_ shape: RoundedRectangle) -> some View {
        if policy.surface == .opaque { shape.fill(palette.pearl) }
        else { shape.fill(.ultraThinMaterial).overlay { shape.fill(palette.glassTint.opacity(palette.finish.glassTintOpacity)) } }
    }

    @ViewBuilder private func jacket(width: CGFloat, height: CGFloat) -> some View {
        let image = EditorialBookJacket(height: height, palette: palette, stance: .shelf) {
            cover(width: width, height: height)
        }
            .brightness(isPressed ? 0.045 : 0)
            .animation(motion.animation(.press), value: isPressed)
        if let heroNamespace { image.bookHeroSource("continue|" + book.id, in: heroNamespace).offset(x: -6, y: 8) }
        else { image.offset(x: -6, y: 8) }
    }

    private func cover(width: CGFloat, height: CGFloat) -> some View {
        AsyncBookCover(urlString: book.coverURL, width: width, height: height,
            baseURLString: book.bookURL, sourceURLString: book.sourceURL,
            onImageLoad: { coverImage = $0 }, title: book.title)
    }

    private func makeMarginNotes(coverWidth: CGFloat) -> some View {
        HStack(alignment: .center, spacing: coverWidth + 24) {
            VStack(spacing: 2) {
                if let number = ReadingDeskContent.chapterNumber(for: book) {
                    Text("第").font(.caption2)
                    Text(number).font(.caption.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                    Text("章").font(.caption2)
                }
            }.frame(maxWidth: .infinity)
            VStack(spacing: 4) {
                Text(ReadingHeroStatus.progress(for: book).replacingOccurrences(of: "章节进度 ", with: ""))
                    .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(2).minimumScaleFactor(0.8)
                if book.lastReadAt != nil, book.totalChapters > 0 { Text("章节进度").font(.caption2) }
            }.frame(maxWidth: .infinity).accessibilityLabel(ReadingHeroStatus.progress(for: book))
        }.foregroundStyle(palette.ink.opacity(0.72)).padding(.horizontal, 12)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 6) {
            if typeSize.isAccessibilitySize {
                Text(book.title).font(titleFont)
                    .fixedSize(horizontal: false, vertical: true)
                if let author { Text(author).font(.caption).foregroundStyle(palette.ink.opacity(0.7)) }
            } else {
                GeometryReader { geometry in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(book.title).font(titleFont).tracking(0.4)
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        if let author {
                            Text(author).font(.caption).lineLimit(1).foregroundStyle(palette.ink.opacity(0.7))
                                .frame(width: geometry.size.width * 0.28, alignment: .trailing)
                        }
                    }
                }.frame(height: titleRowHeight)
            }
            Text(ReadingDeskContent.contextLine(for: book)).font(.caption)
                .foregroundStyle(palette.ink.opacity(0.72)).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            if typeSize.isAccessibilitySize, book.lastReadAt != nil, book.totalChapters > 0 {
                Text(ReadingHeroStatus.progress(for: book))
                    .font(.caption).foregroundStyle(palette.ink.opacity(0.72))
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
    }

    private var titleFont: Font {
        .system(size: titleFontSize, weight: .semibold, design: theme == .classic ? .serif : theme.fontDesign)
    }

    private var author: String? {
        let name = book.author.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func updateEnergyPolicy() {
        conservesEnergy = ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState.rawValue >= 2
    }
}
