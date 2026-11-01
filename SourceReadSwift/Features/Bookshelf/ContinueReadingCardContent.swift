import SwiftUI

/// Content-sized rather than a fixed-height promotion tile. Large text can
/// grow naturally; normal text doesn't pay for an empty second button row.
struct ContinueReadingCardContent<Cover: View>: View {
    let title: String
    let author: String
    let progressText: String
    @ViewBuilder var cover: () -> Cover
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            cover()
            VStack(alignment: .leading, spacing: 5) {
                Text(progressText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                Text(author)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                Label("继续阅读", systemImage: "book.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppLayout.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: AppLayout.minimumTapTarget)
        .contentShape(Rectangle())
    }
}
