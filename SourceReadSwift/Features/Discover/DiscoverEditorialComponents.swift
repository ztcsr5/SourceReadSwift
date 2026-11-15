import SwiftUI

enum DiscoverEditorialPalette {
    // Unlike the lowered system placeholder, this keeps labels readable on tinted paper.
    static let secondaryInk = Color.primary.opacity(0.73)
    static let controlPaper = Color.primary.opacity(0.065)
}

struct DiscoverSectionTabs: View {
    @Binding var selection: DiscoverView.DiscoverTab
    @AppMotion private var motion

    var body: some View {
        HStack(spacing: 24) {
            ForEach(DiscoverView.DiscoverTab.allCases) { tab in
                let isSelected = selection == tab
                Button {
                    selection = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : DiscoverEditorialPalette.secondaryInk)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 48, minHeight: 44)
                        .overlay(alignment: .bottom) {
                            Capsule()
                                .fill(AppTheme.accent)
                                .frame(height: 2)
                                .opacity(isSelected ? 1 : 0)
                                .animation(motion.animation(.press), value: isSelected)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("discover.tab." + (tab == .search ? "search" : "browse"))
            }
            Spacer(minLength: 0)
        }
        .background(alignment: .bottom) { Divider() }
    }
}

struct DiscoverEditorialHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.largeTitle.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(DiscoverEditorialPalette.secondaryInk)
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DiscoverQueryRow: View {
    let query: String
    let index: Int?
    let onSelect: (String) -> Void

    var body: some View {
        Button {
            onSelect(query)
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let index {
                        Text(index.formatted(.number.precision(.integerLength(2))))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    } else {
                        Image(systemName: "clock").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 24, alignment: .leading)
                .accessibilityHidden(true)

                Text(query).font(.body.weight(.medium)).foregroundStyle(.primary)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.left")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DiscoverEditorialPalette.secondaryInk)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
            .background(alignment: .bottom) { Divider().padding(.leading, 40) }
        }
        .buttonStyle(BookOpenPressStyle())
    }
}

/// Keeps text and covers aligned in search, grouped results and browse.
struct DiscoverResultEdition: View {
    let title: String
    let byline: String
    let synopsis: String?
    let coverURL: URL?

    static let jacketWidth: CGFloat = 56
    private static let jacketHeight: CGFloat = 84

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let coverURL {
                    CachedRemoteImage(url: coverURL, maxPixelSize: 260) { DiscoverJacketPlaceholder() }
                } else {
                    DiscoverJacketPlaceholder()
                }
            }
            .frame(width: Self.jacketWidth, height: Self.jacketHeight)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !byline.isEmpty {
                    Text(byline)
                        .font(.subheadline)
                        .foregroundStyle(DiscoverEditorialPalette.secondaryInk)
                        .lineLimit(1)
                }
                if let synopsis, !synopsis.isEmpty {
                    Text(synopsis)
                        .font(.footnote)
                        .foregroundStyle(DiscoverEditorialPalette.secondaryInk)
                        .lineLimit(2)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct DiscoverResultLine: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) {
                Divider()
                    .padding(.leading, DiscoverResultEdition.jacketWidth + 12)
                    .offset(y: 6)
                    .allowsHitTesting(false)
            }
    }
}

struct DiscoverJacketPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(AppTheme.accent.opacity(0.09))
            .overlay(alignment: .leading) {
                Rectangle().fill(AppTheme.accent.opacity(0.14)).frame(width: 4)
            }
            .overlay {
                Image(systemName: "book.closed")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(AppTheme.accent)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct DiscoverBrowseRow: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(AppTheme.accent)
                .accessibilityHidden(true)
            Text(title).foregroundStyle(.primary).layoutPriority(1)
            Spacer(minLength: 4)
            Text(value).foregroundStyle(.secondary).lineLimit(2)
                .multilineTextAlignment(.trailing)
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                .foregroundStyle(DiscoverEditorialPalette.secondaryInk)
                .accessibilityHidden(true)
        }
        .font(.subheadline)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
