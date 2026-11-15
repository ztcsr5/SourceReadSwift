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
    private var ink: Color { Color(hex: isNight ? 0xF8F3EE : 0x211D19) }
    private var pigment: Color { Color(hex: isNight ? edition.darkAccentHex : edition.accentHex) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                editionPicker
                lightingPicker

                if let signature = AtmosphericThemeSignature(theme: edition) {
                    galleryPrint
                    colophon(signature)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .foregroundStyle(ink)
            .environment(\.colorScheme, isNight ? .dark : .light)
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
            Text("同一幅画，两种光线")
                .font(.footnote)
                .foregroundStyle(ink.opacity(0.74))
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("预览光线", selection: $isNight) {
                Text("日间").tag(false)
                Text("夜读").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(idealWidth: 128, maxWidth: 152)
            .accessibilityIdentifier("appearance.atmosphere.light")
        }
    }

    private var galleryPrint: some View {
        Group {
            if let name = edition.atmosphericPaperAsset(isDark: isNight) {
                AtmosphericArtwork(name: name, paper: paper, alignment: .bottom)
            }
        }
        // Keep the caption above the fixed action on compact phones.
        .aspectRatio(1.04, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        return VStack(spacing: 0) {
            Divider()
            Button {
                onApply(edition)
            } label: {
                Label(isApplied ? "正在使用" : "应用主题", systemImage: isApplied ? "checkmark" : "arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(isApplied ? ink : paper)
                    .background(isApplied ? ink.opacity(0.075) : ink, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(AppPressStyle())
            .accessibilityIdentifier("appearance.atmosphere.apply")
            .disabled(isApplied)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity)
        .background(paper, ignoresSafeAreaEdges: .horizontal)
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
