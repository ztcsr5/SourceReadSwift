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
    private static let stageEnvelopeHeight: CGFloat = 214
    // Reserve two scaled Songti lines and the actual reading context.
    @ScaledMetric(relativeTo: .title2) private var metadataHeight: CGFloat = 72
    @ScaledMetric(relativeTo: .title2) private var titleFontSize: CGFloat = 22
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
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let width: CGFloat = geometry.size.width < 310 ? 134 : 152
                let height: CGFloat = geometry.size.width < 310 ? 178 : 202
                ZStack(alignment: .top) {
                    environment.frame(height: Self.stageEnvelopeHeight)
                        .modifier(FloatingDeskParallax(depth: 3 * palette.finish.parallaxStrength, reducesDepth: policy.reducesDepth))
                    stage.frame(height: 132).padding(.top, 82)
                        .modifier(FloatingDeskParallax(depth: 7 * palette.finish.parallaxStrength, reducesDepth: policy.reducesDepth))
                    if !typeSize.isAccessibilitySize {
                        makeMarginNotes(coverWidth: width).padding(.top, 123)
                            .modifier(FloatingDeskParallax(depth: 30 * palette.finish.parallaxStrength, reducesDepth: policy.reducesDepth))
                    }
                    jacket(width: width, height: height).frame(maxWidth: .infinity)
                        .modifier(FloatingDeskParallax(depth: 22 * palette.finish.parallaxStrength, reducesDepth: policy.reducesDepth))
                    ReadingDeskFrontEdge(palette: palette)
                        .frame(height: 4).padding(.top, Self.stageEnvelopeHeight - 4)
                        .modifier(FloatingDeskParallax(depth: 7 * palette.finish.parallaxStrength, reducesDepth: policy.reducesDepth))
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
        ReadingDeskPlinth(palette: palette, policy: policy)
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
            onImageLoad: { coverImage = $0 }, title: book.title, prefersDeskRaster: true, cornerRadius: 3)
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
