import SwiftUI
import UIKit

struct SearchBookRow: View {
    let book: SearchBook
    var sourceKind: BookSourceKind? = nil
    var onAdd: (() -> Void)?
    var isInBookshelf = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            cover

            VStack(alignment: .leading, spacing: 6) {
                Text(book.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(book.author ?? "作者未知")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let sourceKind, sourceKind != .text {
                        HStack(spacing: 3) {
                            Image(systemName: sourceKind.systemImage)
                                .font(.system(size: 9, weight: .bold))
                            Text(sourceKind.displayName)
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(kindBadgeColor(sourceKind))
                        .clipShape(Capsule())
                    }

                    Text(book.sourceName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                }

                if let intro = book.intro, !intro.isEmpty {
                    Text(intro)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(book.bookUrl)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if let onAdd {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onAdd()
                } label: {
                    Image(systemName: isInBookshelf ? "checkmark.circle.fill" : "plus.circle")
                        .font(.title2)
                        .foregroundStyle(isInBookshelf ? Color.green : AppTheme.accent)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var cover: some View {
        if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
            CachedRemoteImage(url: url) { placeholder }
            .frame(width: 74, height: 98)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            placeholder
                .frame(width: 74, height: 98)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.blue.opacity(0.12))
            .overlay {
                Image(systemName: "book")
                    .font(.title)
                    .foregroundStyle(.blue)
            }
    }

    private func kindBadgeColor(_ kind: BookSourceKind) -> Color {
        switch kind {
        case .audio: return Color.purple
        case .comic: return Color.orange
        case .video: return Color.red
        case .text: return Color.blue
        }
    }
}
