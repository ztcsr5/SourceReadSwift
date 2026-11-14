import SwiftUI

/// Keeps typed option values and the existing bindings; only the Forest presentation changes.
struct BrandSegmentedControl<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]
    var symbols: [Value: String] = [:]
    @AppStorage(AppVisualTheme.selectionKey) private var themeRaw = AppVisualTheme.initialSelection.rawValue
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppMotion private var motion
    @Namespace private var highlight

    init(_ title: String, selection: Binding<Value>, options: [(Value, String)], symbols: [Value: String] = [:]) {
        self.title = title
        _selection = selection
        self.options = options
        self.symbols = symbols
    }

    private var theme: AppVisualTheme { AppVisualTheme.migrated(from: themeRaw) }

    var body: some View {
        if theme.usesNeutralGlass {
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
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}
