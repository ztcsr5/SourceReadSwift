import SwiftUI

/// Full-opacity paper, not glass: moving body text must never bleed through
/// the fixed chapter label, even when the system status bar is hidden.
struct ReaderScrollChapterHeader<Status: View>: View {
    let title: String?
    let geometry: ReaderScrollChromeGeometry
    let horizontalPadding: CGFloat
    let foreground: Color
    let paper: Color
    @ViewBuilder var status: () -> Status

    var body: some View {
        ZStack(alignment: .topLeading) {
            paper
            if geometry.headerVisible {
                HStack(spacing: 12) {
                    if let title {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(foreground.opacity(0.82))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 8)
                    status()
                }
                .frame(height: ReaderPageChrome.scrollHeaderBandHeight)
                .padding(.horizontal, max(horizontalPadding, 18))
                .padding(.top, geometry.headerTop)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: geometry.protectedHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
