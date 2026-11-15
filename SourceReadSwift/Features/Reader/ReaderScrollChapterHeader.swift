import SwiftUI

/// Full-opacity paper, not glass: moving body text must never bleed through
/// the fixed chapter label, even when the system status bar is hidden.
struct ReaderScrollChapterHeader<Status: View>: View {
    let title: String?
    let geometry: ReaderScrollChromeGeometry
    let horizontalPadding: CGFloat
    let foreground: Color
    let paper: Color
    var textOpacity: Double = 0.82
    var showsLabels = true
    var wallpaper: AnyView? = nil
    var showDivider: Bool = false
    var customStrip: (() -> AnyView)? = nil
    @ViewBuilder var status: () -> Status

    var body: some View {
        ZStack(alignment: .topLeading) {
            paper
            if let wallpaper { wallpaper }
            if geometry.headerVisible {
                VStack(spacing: 0) {
                    Group {
                        if let customStrip {
                            customStrip()
                        } else {
                            HStack(spacing: 12) {
                                if let title {
                                    Text(title)
                                        .font(.system(size: geometry.fontSize, weight: .medium))
                                        .foregroundStyle(foreground.opacity(textOpacity))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                Spacer(minLength: 8)
                                status()
                            }
                        }
                    }
                    .frame(height: geometry.bandHeight)
                    .padding(.horizontal, max(horizontalPadding, 18))
                    .padding(.top, geometry.headerTop)

                    if showDivider {
                        Rectangle()
                            .fill(foreground.opacity(0.10))
                            .frame(height: 0.5)
                            .padding(.horizontal, max(horizontalPadding, 18))
                    }
                }
                .opacity(showsLabels ? 1 : 0)
                .accessibilityHidden(!showsLabels)
                .animation(nil, value: showsLabels)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: geometry.protectedHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
