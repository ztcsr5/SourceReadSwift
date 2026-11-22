import SwiftUI

struct ForestGlassBackdrop: View {
    var body: some View {
        MistPaperWash(paper: AppVisualTheme.forest.mistPaper, edge: AppVisualTheme.forest.mistTint)
    }
}

/// Two stationary ramps keep colour at the edge rather than tinting the entire sheet.
struct MistPaperWash: View {
    let paper: Color
    let edge: Color
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            paper
            if !reducesTransparency, contrast != .increased {
                LinearGradient(stops: [.init(color: edge, location: 0.12), .init(color: paper, location: 0.65)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                LinearGradient(stops: [.init(color: paper.opacity(0.90), location: 0),
                    .init(color: paper.opacity(0), location: 0.32),
                    .init(color: paper.opacity(0), location: 0.52), .init(color: paper, location: 1)],
                    startPoint: .top, endPoint: .bottom)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
