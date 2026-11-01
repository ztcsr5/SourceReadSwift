import SwiftUI

/// One material per panel. Nesting glass on every button obscures both labels
/// and the paper beneath it; accessibility always has an opaque escape hatch.
struct ReaderChromeSurface: ViewModifier {
    let paper: Color
    let ink: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    static func usesNativeGlass(reduceTransparency: Bool) -> Bool {
        guard !reduceTransparency else { return false }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular.tint(paper.opacity(0.25)),
                                in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            opaque(content)
        }
        #else
        opaque(content)
        #endif
    }

    private func opaque(_ content: Content) -> some View {
        content
            .background(paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(ink.opacity(0.18), lineWidth: 0.6)
                    .allowsHitTesting(false)
            }
    }
}
