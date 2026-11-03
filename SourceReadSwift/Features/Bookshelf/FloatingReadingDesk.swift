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
    @Environment(\.readingCoverHandoff) private var readingCoverHandoff
    @AppStorage("settings.visualTheme") private var themeRaw = AppVisualTheme.classic.rawValue
    @AppStorage("settings.appearanceRevision") private var appearanceRevision = 0
    @AppMotion private var motion
    @ScaledMetric(relativeTo: .title3) private var titleRowHeight = 26
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
        VStack(spacing: 12) {
            GeometryReader { geometry in
                let width: CGFloat = geometry.size.width < 310 ? 156 : 168
                let height: CGFloat = geometry.size.width < 310 ? 208 : 224
                ZStack(alignment: .top) {
                    environment.frame(height: 248)
                        .modifier(FloatingDeskParallax(depth: 3 * palette.finish.parallaxStrength, reducesDepth: policy.reducesDepth))
                    stage.frame(height: 148).padding(.top, 88)
                        .modifier(FloatingDeskParallax(depth: 7 * palette.finish.parallaxStrength, reducesDepth: policy.reducesDepth))
                    sideNotes(coverWidth: width).padding(.top, 132)
                        .modifier(FloatingDeskParallax(depth: 30 * palette.finish.parallaxStrength, reducesDepth: policy.reducesDepth))
                    jacket(width: width, height: height).frame(maxWidth: .infinity)
                        .modifier(FloatingDeskParallax(depth: 22 * palette.finish.parallaxStrength, reducesDepth: policy.reducesDepth))
                }
            }.frame(height: 240)
            caption
                .modifier(FloatingDeskParallax(depth: 34 * palette.finish.parallaxStrength, reducesDepth: policy.reducesDepth))
        }
        .foregroundStyle(palette.ink)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("轻点打开书籍，长按管理")
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
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                Ellipse().fill(RadialGradient(colors: [palette.shadow.opacity(scheme == .dark ? 0.28 : 0.13), .clear],
                    center: .center, startRadius: 0, endRadius: 84))
                    .frame(width: 190, height: 20).offset(y: 59)
            }
        }.overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(palette.ink.opacity(0.45), lineWidth: 1.5)
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [palette.pearl.opacity(0.85), palette.mist.opacity(0.10), palette.pearl.opacity(0.28)],
                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
            }
        }
        .shadow(color: palette.shadow.opacity(contrast == .increased ? 0 : 0.06), radius: 12, y: 8)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var glassPlane: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
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

    private func jacket(width: CGFloat, height: CGFloat) -> some View {
        cover(width: width, height: height)
            .overlay(alignment: .leading) {
                LinearGradient(colors: [palette.shadow.opacity(0.24), palette.pearl.opacity(0.30), .clear],
                    startPoint: .leading, endPoint: .trailing).frame(width: 10)
            }
            .overlay(alignment: .trailing) {
                Rectangle().fill(palette.pearl.opacity(0.8)).frame(width: 2).padding(.vertical, 5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.pearl.opacity(0.35), lineWidth: 0.5))
            .shadow(color: palette.shadow.opacity(scheme == .dark ? 0.35 : 0.20), radius: 14, x: 6, y: 12)
            .brightness(isPressed ? 0.045 : 0)
            .animation(motion.animation(.press), value: isPressed)
            .accessibilityHidden(true)
    }

    @ViewBuilder private func cover(width: CGFloat, height: CGFloat) -> some View {
        let image = AsyncBookCover(urlString: book.coverURL, width: width, height: height,
            baseURLString: book.bookURL, sourceURLString: book.sourceURL,
            onImageLoad: { image in
                coverImage = image
                if let image, let url = CoverURLResolver.url(from: book.coverURL, base: book.bookURL, fallbackBase: book.sourceURL) {
                    readingCoverHandoff?.retain(image, for: url)
                }
            }, title: book.title)
        if let heroNamespace { image.bookHeroSource("continue|" + book.id, in: heroNamespace) }
        else { image }
    }

    private func sideNotes(coverWidth: CGFloat) -> some View {
        HStack(alignment: .center, spacing: coverWidth + 24) {
            VStack(spacing: 6) {
                Image(systemName: "bookmark").font(.system(size: 16, weight: .light))
                Text(book.hasUpdates ? "有更新" : "续读").font(.system(size: 12, weight: .medium))
            }.frame(maxWidth: .infinity)
            Text(ReadingHeroStatus.progress(for: book).replacingOccurrences(of: "章节进度 ", with: ""))
                .font(.system(size: 16, weight: .medium, design: .rounded)).monospacedDigit()
                .lineLimit(2).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
                .accessibilityLabel(ReadingHeroStatus.progress(for: book))
        }.foregroundStyle(palette.ink.opacity(0.72)).padding(.horizontal, 12)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 6) {
            if typeSize.isAccessibilitySize {
                Text(book.title).font(.system(.title3, design: theme.fontDesign).weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(book.author.isEmpty ? "作者未记录" : book.author).font(.caption)
                    .foregroundStyle(palette.ink.opacity(0.7))
            } else {
                GeometryReader { geometry in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(book.title).font(.system(.title3, design: theme.fontDesign).weight(.semibold))
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(book.author.isEmpty ? "作者未记录" : book.author).font(.caption)
                            .lineLimit(1).foregroundStyle(palette.ink.opacity(0.7))
                            .frame(width: geometry.size.width * 0.28, alignment: .trailing)
                    }
                }.frame(height: titleRowHeight)
            }
            Text(ReadingHeroStatus.chapter(for: book)).font(.caption)
                .foregroundStyle(palette.ink.opacity(0.72)).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
    }

    private func updateEnergyPolicy() {
        conservesEnergy = ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState.rawValue >= 2
    }
}
