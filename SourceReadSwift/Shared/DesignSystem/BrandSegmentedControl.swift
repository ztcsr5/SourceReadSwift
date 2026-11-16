import SwiftUI

/// Keeps typed option values and the existing bindings; adapts presentation for Forest and edition themes.
struct BrandSegmentedControl<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]
    var symbols: [Value: String] = [:]
    var accentOverride: Color? = nil
    var paperOverride: Color? = nil
    @AppStorage(AppVisualTheme.selectionKey) private var themeRaw = AppVisualTheme.initialSelection.rawValue
    @Environment(\.readingEdition) private var envSkin
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppMotion private var motion
    @Namespace private var highlight

    init(_ title: String, selection: Binding<Value>, options: [(Value, String)],
         symbols: [Value: String] = [:], accent: Color? = nil, paper: Color? = nil) {
        self.title = title
        _selection = selection
        self.options = options
        self.symbols = symbols
        self.accentOverride = accent
        self.paperOverride = paper
    }

    private var theme: AppVisualTheme { AppVisualTheme.migrated(from: themeRaw) }
    private var activeSkin: ReadingEditionSkin? { envSkin ?? ReadingEditionSkin(theme: theme) }

    var body: some View {
        if let skin = activeSkin {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 3))
            let shape = EditionContour(skin: skin)
            let accent = accentOverride ?? AppTheme.accent
            let paper = paperOverride ?? AppTheme.card

            layout {
                ForEach(options.indices, id: \.self) { index in
                    editionOption(options[index].0, label: options[index].1, skin: skin, accent: accent, paper: paper)
                }
            }
            .padding(3.5)
            .background {
                shape.fill(accent.opacity(skin == .bunny ? 0.11 : 0.06))
                    .overlay {
                        shape.stroke(
                            accent.opacity(skin == .blade ? 0.55 : skin == .ink ? 0.36 : 0.28),
                            style: skin == .bunny
                                ? StrokeStyle(lineWidth: 1.2, dash: [4, 3])
                                : StrokeStyle(lineWidth: skin == .blade ? 1.3 : 1.0)
                        )
                    }
            }
            .animation(motion.animation(.navigation), value: selection)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        } else if theme.usesNeutralGlass {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
            layout {
                ForEach(options.indices, id: \.self) { index in
                    option(options[index].0, label: options[index].1)
                }
            }
            .padding(3)
            .background { BrandGlass(outline: RoundedRectangle(cornerRadius: 24)) }
            .animation(motion.animation(.navigation), value: selection)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        } else {
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { index in
                    Text(options[index].1).tag(options[index].0)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func editionOption(_ value: Value, label: String, skin: ReadingEditionSkin, accent: Color, paper: Color) -> some View {
        let isSelected = selection == value
        let indicatorShape = EditionContour(skin: skin)
        return Button {
            guard selection != value else { return }
            HapticFeedback.light()
            selection = value
        } label: {
            HStack(spacing: 5) {
                if let symbol = symbols[value] {
                    EditionGlyph(systemName: symbol, size: 13, weight: isSelected ? .bold : .medium)
                }
                Text(label)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.center)
            }
            .font(.subheadline.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? paper : accent.opacity(0.84))
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background {
                if isSelected {
                    indicatorShape.fill(accent)
                        .overlay(alignment: .bottomTrailing) {
                            EditionEdgeMark(skin: skin, ink: paper)
                                .frame(width: 14, height: 5)
                                .padding(.trailing, skin == .bunny ? 10 : 5)
                                .padding(.bottom, 2)
                                .opacity(0.65)
                        }
                        .matchedGeometryEffect(id: "selection", in: highlight)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(AppPressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func option(_ value: Value, label: String) -> some View {
        Button {
            guard selection != value else { return }
            HapticFeedback.light()
            selection = value
        } label: {
            HStack(spacing: 5) {
                if let symbol = symbols[value] { Image(systemName: symbol) }
                Text(label).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.center)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(selection == value ? AppTheme.accent : theme.secondaryInk)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if selection == value {
                    Capsule().fill(theme.controlFill)
                        .overlay(Capsule().strokeBorder(theme.controlBorder, lineWidth: 0.5))
                        .matchedGeometryEffect(id: "selection", in: highlight)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(AppPressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}
