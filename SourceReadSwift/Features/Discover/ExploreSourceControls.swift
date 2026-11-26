import SwiftUI

/// Presents source-defined actions; the surrounding container owns their execution.
struct ExploreSourceControls: View {
    let controls: [SourceExploreControl]
    @Binding var inputs: [String: String]
    let isLoading: Bool
    let message: String?
    let onAction: (SourceExploreControl) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(controls.filter { $0.kind == .select }) { control in
                HStack(spacing: 12) {
                    Text(control.title).font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Picker(control.title, selection: Binding(
                        get: { inputs[control.title] ?? control.defaultValue },
                        set: {
                            inputs[control.title] = $0
                            onAction(control)
                        }
                    )) {
                        if !control.choices.contains(inputs[control.title] ?? control.defaultValue) {
                            Text(inputs[control.title] ?? control.defaultValue).tag(inputs[control.title] ?? control.defaultValue)
                        }
                        ForEach(control.choices, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(isLoading)
                    .accessibilityLabel(control.title)
                    .accessibilityIdentifier("discover.sourceSelect." + control.id)
                }
            }
            ForEach(controls.filter { $0.kind == .text }) { control in
                VStack(alignment: .leading, spacing: 4) {
                    Text(control.title).font(.caption).foregroundStyle(.secondary)
                    TextField(control.title, text: Binding(
                        get: { inputs[control.title] ?? control.defaultValue },
                        set: { inputs[control.title] = String($0.prefix(500)) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .disabled(isLoading)
                }
            }
            if controls.contains(where: { $0.kind == .button }) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                    ForEach(controls.filter { $0.kind == .button }) { control in
                        Button { onAction(control) } label: {
                            Text(control.title).font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.accent)
                        .disabled(isLoading)
                    }
                }
            }
            if let message { Text(message).font(.footnote).foregroundStyle(.secondary).accessibilityAddTraits(.updatesFrequently) }
        }
    }
}
