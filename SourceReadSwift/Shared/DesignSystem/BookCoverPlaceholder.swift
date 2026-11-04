import SwiftUI

/// An opaque, theme-owned book jacket; never inherits NavigationLink's tint or dark ink.
struct BookCoverPlaceholder: View {
    let title: String?
    let height: CGFloat
    var isOnDark = false
    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppVisualTheme.selectionKey) private var themeRaw = AppVisualTheme.initialSelection.rawValue

    private var theme: AppVisualTheme { AppVisualTheme(rawValue: themeRaw) ?? .classic }
    private var isDark: Bool { isOnDark || scheme == .dark }
    private var paper: Color { Color(uiColor: AppVisualTheme.uiColor(isDark ? theme.darkCardHex : theme.cardHex)) }
    private var ink: Color { Color(uiColor: AppVisualTheme.uiColor(isDark ? theme.darkAccentHex : theme.accentHex)) }

    var body: some View {
        ZStack(alignment: .leading) {
            paper
            Rectangle().fill(ink.opacity(0.25)).frame(width: 2).padding(.leading, 7)
            VStack(spacing: 8) {
                Image(systemName: "book.closed")
                    .font(.system(size: max(16, min(height * 0.16, 28)), weight: .light))
                    .symbolRenderingMode(.monochrome)
                if let title, !title.isEmpty, height >= 90 {
                    Text(title).font(.system(size: min(height * 0.09, 14), weight: .medium, design: .serif))
                        .lineLimit(3).multilineTextAlignment(.center)
                }
            }.padding(.horizontal, 16).frame(maxWidth: .infinity)
        }
        .foregroundStyle(ink)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ink.opacity(0.18), lineWidth: 1))
        .accessibilityLabel(title.map { "\($0)，暂无封面" } ?? "暂无封面")
    }
}
