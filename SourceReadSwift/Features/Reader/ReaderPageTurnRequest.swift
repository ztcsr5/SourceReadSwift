import CoreGraphics

/// Tap input is a request, not a cursor write. UIKit commits the cursor only
/// after the same animation transaction used by a swipe has finished.
@MainActor
final class ReaderPageTurnRequest {
    let direction: Int
    let originNormalized: CGPoint?
    private let pageIdentity: String?
    private let style: CoverPageTurnStyle?
    private(set) var isConsumed = false

    init(direction: Int, pageIdentity: String? = nil, style: CoverPageTurnStyle? = nil, originNormalized: CGPoint? = nil) {
        self.direction = direction
        self.pageIdentity = pageIdentity
        self.style = style
        self.originNormalized = originNormalized
    }

    /// Only the matching page and effect may consume this request.
    func claim(pageIdentity: String? = nil, style: CoverPageTurnStyle? = nil) -> Bool {
        guard !isConsumed,
              self.pageIdentity == nil || self.pageIdentity == pageIdentity,
              self.style == nil || self.style == style
        else { return false }
        isConsumed = true
        return true
    }

    /// A delivered tap is one-shot even when its original page is already gone.
    func discard() {
        isConsumed = true
    }
}
