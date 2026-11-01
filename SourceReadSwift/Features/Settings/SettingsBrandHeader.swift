import SwiftUI

struct SettingsBrandHeader: View {
    let readingNote: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PaperBetweenMark()
            VStack(alignment: .leading, spacing: 7) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        title
                        version
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 4) {
                        title
                        version
                    }
                }
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    private var title: some View { Text("纸间").font(.title3.weight(.semibold)) }
    private var version: some View {
        Text(AppVersion.fullDisplayString)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
    }
}
