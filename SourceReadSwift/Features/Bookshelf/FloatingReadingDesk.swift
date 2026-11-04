import SwiftUI

/// A complete book floats across one shallow glass plane; metadata stays outside the glass.
struct FloatingReadingDesk: View {
    let book: BookshelfBook
    var heroNamespace: Namespace.ID? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @AppStorage("settings.visualTheme") private var themeRaw = AppVisualTheme.classic.rawValue
    @AppStorage("settings.appearanceRevision") private var appearanceRevision = 0
    @AppMotion private var motion
    // Reserve room for two title lines without changing the measured desk height.
    private static let stageEnvelopeHeight: CGFloat = 204
    // Two regular Songti lines, caption and spacing measured 75.67 pt on iOS 26.
    @ScaledMetric(relativeTo: .title2) private var metadataHeight: CGFloat = 78
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
                let width: CGFloat = geometry.size.width < 310 ? 134 : 146
                let height: CGFloat = geometry.size.width < 310 ? 182 : 194
                ZStack(alignment: .top) {
                    environment.frame(height: Self.stageEnvelopeHeight)
                        .modifier(FloatingDeskParallax(depth: 3 * palette.finish.parallaxStrength, reducesDepth: policy.reducesDepth))
                    stage.frame(height: 116).padding(.top, 83)
                        .modifier(FloatingDeskParallax(depth: 7 * palette.finish.parallaxStrength, reducesDepth: policy.reducesDepth))
                    if !typeSize.isAccessibilitySize {
                        makeMarginNotes(coverWidth: width).padding(.top, 111)
                            .modifier(FloatingDeskParallax(depth: 30 * palette.finish.parallaxStrength, reducesDepth: policy.reducesDepth))
                    }
                    jacket(width: width, height: height).frame(maxWidth: .infinity)
                        .modifier(FloatingDeskParallax(depth: 22 * palette.finish.parallaxStrength, reducesDepth: policy.reducesDepth))
                }
            }.frame(height: Self.stageEnvelopeHeight)
            caption
                .modifier(FloatingDeskParallax(depth: 34 * palette.finish.parallaxStrength, reducesDepth: policy.reducesDepth))
        }
        .foregroundStyle(palette.ink)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("轻点继续阅读，使用更多操作管理")
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
            if policy.surface != .opaque {
                RadialGradient(colors: [palette.light.opacity(scheme == .dark ? 0.18 : 0.40), .clear],
                    center: UnitPoint(x: 0.52, y: 0.64), startRadius: 12, endRadius: 164)
                RadialGradient(colors: [pigment.opacity(scheme == .dark ? 0.06 : 0.09), .clear],
                    center: UnitPoint(x: 0.33, y: 0.44), startRadius: 0, endRadius: 124)
            }
        }.opacity(palette.finish.environmentStrength).allowsHitTesting(false)
    }

    private var pigment: Color {
        tone.map { Color(red: $0.vividRed, green: $0.vividGreen, blue: $0.vividBlue) } ?? palette.mist
    }

    private var stage: some View {
        let outline = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return glassPlane
            .overlay {
                if policy.surface != .opaque {
                    // Darker near the lower edge so the jacket stands on a plane,
                    // rather than on the centre of a uniformly white tile.
                    outline.fill(LinearGradient(stops: [
                        .init(color: palette.pearl.opacity(scheme == .dark ? 0.06 : 0.26), location: 0),
                        .init(color: .clear, location: 0.38),
                        .init(color: palette.light.opacity(scheme == .dark ? 0.13 : 0.24), location: 0.77),
                        .init(color: palette.shadow.opacity(scheme == .dark ? 0.20 : 0.14), location: 1)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .modifier(PearlGlassFinish(outline: outline, pearl: palette.pearl, mist: palette.light))
                }
            }
            .overlay(alignment: .bottom) {
                if policy.surface != .opaque {
                    Ellipse().fill(RadialGradient(colors: [
                        palette.shadow.opacity(scheme == .dark ? 0.50 : 0.31), .clear
                    ], center: .center, startRadius: 0, endRadius: 74))
                    .frame(width: 150, height: 12)
                    .offset(x: 5, y: 2)
                }
            }
            .overlay {
                if policy.surface == .opaque {
                    outline.strokeBorder(palette.ink.opacity(contrast == .increased ? 0.45 : 0.18),
                        lineWidth: contrast == .increased ? 1.5 : 0.75)
                }
            }
            .shadow(color: palette.shadow.opacity(policy.surface == .opaque ? 0 : 0.09), radius: 10, y: 6)
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
        // Both sizes sit on the same stage line, including narrow-screen covers.
        let elevation = Self.stageEnvelopeHeight - height - 8
        if let heroNamespace { image.bookHeroSource("continue|" + book.id, in: heroNamespace).offset(y: elevation) }
        else { image.offset(y: elevation) }
    }

    private func cover(width: CGFloat, height: CGFloat) -> some View {
        AsyncBookCover(urlString: book.coverURL, width: width, height: height,
            baseURLString: book.bookURL, sourceURLString: book.sourceURL,
            onImageLoad: { coverImage = $0 }, title: book.title, prefersDeskRaster: true)
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
                Text(ReadingHeroStatus.progressValue(for: book))
                    .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(2).minimumScaleFactor(0.8)
                if book.lastReadAt != nil, book.totalChapters > 0 { Text("全书进度").font(.caption2) }
            }.frame(maxWidth: .infinity).accessibilityLabel(ReadingHeroStatus.progress(for: book))
        }.foregroundStyle(palette.ink.opacity(0.72)).padding(.horizontal, 12)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            if typeSize.isAccessibilitySize {
                title
                if let author { Text(author).font(.caption).foregroundStyle(palette.ink.opacity(0.7)) }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    title.frame(maxWidth: .infinity, alignment: .leading)
                    if let author {
                        Text(author).font(.caption).lineLimit(1).foregroundStyle(palette.ink.opacity(0.7))
                            .frame(maxWidth: 86, alignment: .trailing)
                    }
                }
            }
            Text(ReadingDeskContent.contextLine(for: book)).font(.caption)
                .foregroundStyle(palette.ink.opacity(0.72)).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            if typeSize.isAccessibilitySize, book.lastReadAt != nil, book.totalChapters > 0 {
                Text(ReadingHeroStatus.progress(for: book))
                    .font(.caption).foregroundStyle(palette.ink.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? nil : metadataHeight, alignment: .topLeading)
        .padding(.horizontal, 8)
    }

    private var title: some View {
        Text(book.title)
            .font(ReadingDeskTitleTypography.font(size: titleFontSize))
            .tracking(0.3)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(book.title)
    }

    private var author: String? {
        let name = book.author.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func updateEnergyPolicy() {
        conservesEnergy = ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState.rawValue >= 2
    }
}
