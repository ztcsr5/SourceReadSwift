import SwiftUI

struct SettingsBrandHeader: View {
    let readingNote: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        PaperBetweenMark()
                        title.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    note
                }
            } else {
                compactHeader
            }
        }
        .padding(.vertical, 2)
    }

    private var compactHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            PaperBetweenMark()
            VStack(alignment: .leading, spacing: 7) {
                identity
                note
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var identity: some View {
        title
    }

    private var note: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "quote.opening")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.accent.opacity(0.8))
                .accessibilityHidden(true)
            Text(readingNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityLabel("阅读小笺，\(readingNote)")
                .accessibilityIdentifier("settings.reading-note")
        }
    }

    private var title: some View { Text("纸间").font(.title3.weight(.semibold)) }
    private var version: some View {
        Text(AppVersion.fullDisplayString)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
    }
}
