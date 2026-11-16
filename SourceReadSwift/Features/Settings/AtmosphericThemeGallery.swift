import SwiftUI

/// A proofing view: changing the edition or lighting does not apply preferences.
struct AtmosphericThemeGallery: View {
    @Binding var appliedThemeRaw: String
    let onApply: (AppVisualTheme) -> Void
    @State private var edition: AppVisualTheme
    @State private var isNight: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 36

    init(appliedThemeRaw: Binding<String>, isDark: Bool, onApply: @escaping (AppVisualTheme) -> Void) {
        _appliedThemeRaw = appliedThemeRaw
        let applied = AppVisualTheme.migrated(from: appliedThemeRaw.wrappedValue)
        _edition = State(initialValue: AppVisualTheme.atmosphericThemes.contains(applied) ? applied : .shuimo)
        _isNight = State(initialValue: isDark)
        self.onApply = onApply
    }

    private var paper: Color { Color(hex: isNight ? edition.darkCardHex : edition.cardHex) }
    private var ink: Color { Color(hex: isNight ? 0xF6F6F6 : 0x1A1A1A) }
    private var pigment: Color { Color(hex: isNight ? edition.darkAccentHex : edition.accentHex) }
    private var skin: ReadingEditionSkin? { ReadingEditionSkin(theme: edition) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                editionPicker
                lightingPicker

                if let signature = AtmosphericThemeSignature(theme: edition) {
                    colophon(signature)
                    if skin != nil {
                        EditionInteractionSample(ink: pigment, foregroundInk: ink, paper: paper)
                    }
                    galleryPrint
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .foregroundStyle(ink)
            .environment(\.colorScheme, isNight ? .dark : .light)
            .environment(\.readingEdition, skin)
        }
        // Preview ink stops at the native navigation and tab chrome. The
        // hosting controller still owns status-bar legibility in the real app mode.
        .background(paper, ignoresSafeAreaEdges: .horizontal)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            applyBar
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("主题画册")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var editionPicker: some View {
        ViewThatFits(in: .horizontal) {
            editionButtons
            ScrollView(.horizontal, showsIndicators: false) { editionButtons }
        }
        .background(alignment: .bottom) { ink.opacity(0.13).frame(height: 1) }
    }

    private var editionButtons: some View {
        HStack(spacing: 4) {
            ForEach(AppVisualTheme.atmosphericThemes) { theme in
                if let signature = AtmosphericThemeSignature(theme: theme) {
                    let isSelected = edition == theme
                    Button {
                        edition = theme
                    } label: {
                        Text(signature.shortTitle)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? ink : ink.opacity(0.72))
                            .fixedSize()
                            .frame(minWidth: 44, minHeight: 44)
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(pigment).frame(height: 2)
                                    .opacity(isSelected ? 1 : 0)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(BookOpenPressStyle())
                    .accessibilityLabel(theme.title)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("appearance.atmosphere.edition." + theme.rawValue)
                }
            }
        }
    }

    private var lightingPicker: some View {
        HStack(spacing: 12) {
            Text("光线与控件")
                .font(.footnote)
                .foregroundStyle(ink.opacity(0.74))
                .frame(maxWidth: .infinity, alignment: .leading)
            BrandSegmentedControl(
                "预览光线",
                selection: $isNight,
                options: [(false, "日间"), (true, "夜读")],
                symbols: [false: "sun.max", true: "moon.stars"],
                accent: pigment,
                paper: paper
            )
            .frame(idealWidth: 164, maxWidth: 186)
            .accessibilityIdentifier("appearance.atmosphere.light")
        }
    }

    private var galleryPrint: some View {
        let shape = skin.map { AnyShape(EditionContour(skin: $0)) } ?? AnyShape(RoundedRectangle(cornerRadius: 12))
        return Group {
            if let name = edition.atmosphericPaperAsset(isDark: isNight) {
                AtmosphericArtwork(name: name, paper: paper, alignment: skin == .sky ? .center : .bottom)
            }
        }
        .aspectRatio(skin == nil ? 1.18 : 1.16, contentMode: .fit)
        .clipShape(shape)
        .overlay {
            if let skin {
                ZStack {
                    EditionContour(skin: skin)
                        .stroke(
                            pigment.opacity(skin == .blade ? 0.65 : skin == .ink ? 0.42 : 0.34),
                            style: skin == .bunny
                                ? StrokeStyle(lineWidth: 1.6, dash: [6, 4])
                                : StrokeStyle(lineWidth: skin == .blade ? 1.6 : 1.1)
                        )
                    EditionCornerTrim(skin: skin, ink: pigment, inset: 8)
                }
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            if let skin {
                EditionSigil(skin: skin, ink: pigment)
                    .frame(width: 26, height: 26)
                    .frame(width: 42, height: 42)
                    .background(paper.opacity(0.92), in: EditionContour(skin: skin))
                    .overlay {
                        EditionContour(skin: skin)
                            .stroke(pigment.opacity(skin == .blade ? 0.60 : 0.32), lineWidth: 1.1)
                    }
                    .padding(12)
            }
        }
        .accessibilityHidden(true)
    }

    private func colophon(_ signature: AtmosphericThemeSignature) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(signature.catalogueNumber + " / " + AppVisualTheme.atmosphericThemes.count.formatted(.number.precision(.integerLength(2))))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(pigment)
                    .accessibilityHidden(true)
                Spacer()
                HStack(spacing: 5) {
                    ForEach(EditionSwatch.allCases, id: \.self) { swatch in
                        Circle().fill(swatch.color(for: edition, isNight: isNight))
                            .overlay { Circle().strokeBorder(ink.opacity(0.20), lineWidth: 1) }
                            .frame(width: 13, height: 13)
                    }
                }
                .accessibilityHidden(true)
            }
            Text(edition.title)
                .font(edition.titleFont(size: titleSize, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(signature.caption)
                .font(.subheadline)
                .foregroundStyle(ink.opacity(0.77))
                .accessibilityIdentifier("appearance.atmosphere.caption")
        }
    }

    private var applyBar: some View {
        let isApplied = appliedThemeRaw == edition.rawValue
        let actionTitle = isApplied ? "正在使用" : "应用主题"
        return VStack(spacing: 0) {
            Divider()
            Button {
                guard appliedThemeRaw != edition.rawValue else { return }
                appliedThemeRaw = edition.rawValue
                onApply(edition)
            } label: {
                EditionActionLabel(actionTitle, systemImage: isApplied ? "checkmark" : "arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .modifier(EditionControlFinish(ink: pigment, paper: paper, role: isApplied ? .secondary : .primary,
                        legacyFill: isApplied ? ink.opacity(0.075) : ink, legacyInk: isApplied ? ink : paper))
                    .contentShape(Rectangle())
            }
            // The bottom action shares the tab bar's scroll edge. Keep its touch frame stationary.
            .buttonStyle(BookOpenPressStyle())
            .accessibilityLabel(actionTitle)
            .accessibilityIdentifier("appearance.atmosphere.apply")
            .disabled(isApplied)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity)
        .background(paper, ignoresSafeAreaEdges: .horizontal)
        .environment(\.readingEdition, skin)
        .environment(\.colorScheme, isNight ? .dark : .light)
    }
}

/// The production button faces and interactive controls matching each edition skin.
private struct EditionInteractionSample: View {
    let ink: Color
    let foregroundInk: Color
    let paper: Color
    @Environment(\.readingEdition) private var skin
    @State private var previewBookmark = false
    @State private var sampleTab = 0
    @State private var sampleSlider = 0.64
    @State private var sampleSwitch = true

    var body: some View {
        let shape = skin.map { AnyShape(EditionContour(skin: $0)) } ?? AnyShape(RoundedRectangle(cornerRadius: 14))
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                EditionHeadingLabel(title: "主题交互控件样张", font: .footnote.weight(.semibold), ink: ink, isCompact: true)
                Spacer()
                HStack(spacing: 10) {
                    ForEach(["chevron.left", "speaker.wave.2", "highlighter", "ellipsis.circle"], id: \.self) { symbol in
                        EditionGlyph(systemName: symbol, size: 13, weight: .semibold)
                            .foregroundStyle(foregroundInk.opacity(0.86))
                            .frame(width: 28, height: 28)
                            .modifier(EditionControlFinish(ink: ink, paper: paper, role: .quiet))
                    }
                }
            }

            BrandSegmentedControl(
                "样张分栏",
                selection: $sampleTab,
                options: [(0, "目录"), (1, "笔记"), (2, "版式")],
                symbols: [0: "list.bullet", 1: "bookmark", 2: "slider.horizontal.3"],
                accent: ink,
                paper: paper
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(skin == .blade ? "剑气游标滑轨" : skin == .ink ? "印石游舟滑轨" : skin == .bunny ? "兔耳奶油滑轨" : "进度滑轨")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(foregroundInk.opacity(0.76))
                    Spacer()
                    Text("\(Int(sampleSlider * 100))%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(ink)
                }
                EditionSlider(value: $sampleSlider, range: 0...1, ink: ink, paper: paper)
            }

            EditionDivider(ink: ink, verticalPadding: 1)

            Toggle(isOn: $sampleSwitch) {
                HStack(spacing: 6) {
                    EditionGlyph(systemName: sampleSwitch ? "play.fill" : "pause.fill", size: 13)
                        .foregroundStyle(ink)
                    Text(skin == .blade ? "飞白切角开关" : skin == .ink ? "朱印宣纸开关" : skin == .bunny ? "软萌兔耳开关" : "主题开关")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(foregroundInk.opacity(0.90))
                }
            }
            .editionToggleStyle(ink: ink, paper: paper)

            Button {
                previewBookmark.toggle()
            } label: {
                EditionActionLabel(previewBookmark ? "已加书签 · 预览" : "添加书签 · 预览",
                                  systemImage: previewBookmark ? "bookmark.fill" : "bookmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .modifier(EditionControlFinish(ink: ink, paper: paper, isSelected: previewBookmark))
            }
            .buttonStyle(AppPressStyle())
            .accessibilityAddTraits(previewBookmark ? .isSelected : [])
            .accessibilityIdentifier("appearance.atmosphere.bookmarkSample")
        }
        .padding(14)
        .background {
            shape.fill(foregroundInk.opacity(skin == .bunny ? 0.035 : 0.03))
                .overlay {
                    shape.stroke(
                        ink.opacity(skin == .blade ? 0.45 : skin == .ink ? 0.30 : 0.25),
                        style: skin == .bunny
                            ? StrokeStyle(lineWidth: 1.3, dash: [5, 3])
                            : StrokeStyle(lineWidth: skin == .blade ? 1.4 : 1.0)
                    )
                }
        }
        .overlay {
            if let skin {
                EditionCornerTrim(skin: skin, ink: ink, inset: 6)
            }
        }
    }
}

private enum EditionSwatch: CaseIterable, Hashable {
    case paper, trim, pigment

    func color(for edition: AppVisualTheme, isNight: Bool) -> Color {
        let rgb: UInt32
        switch self {
        case .paper: rgb = isNight ? edition.darkBackgroundHex : edition.backgroundHex
        case .trim: rgb = isNight ? edition.darkSecondaryHex : edition.secondaryHex
        case .pigment: rgb = isNight ? edition.darkAccentHex : edition.accentHex
        }
        return Color(hex: rgb)
    }
}
