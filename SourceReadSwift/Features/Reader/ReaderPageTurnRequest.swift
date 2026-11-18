/// Tap input is a request, not a cursor write. UIKit commits the cursor only
/// after the same animation transaction used by a swipe has finished.
@MainActor
final class ReaderPageTurnRequest {
    let direction: Int
    private let pageIdentity: String?
    private let style: CoverPageTurnStyle?
    private var isClaimed = false

    init(direction: Int, pageIdentity: String? = nil, style: CoverPageTurnStyle? = nil) {
        self.direction = direction
        self.pageIdentity = pageIdentity
        self.style = style
    }

    /// First delivery owns the request, even if its original page or mode has gone away.
    func claim(pageIdentity: String? = nil, style: CoverPageTurnStyle? = nil) -> Bool {
        guard !isClaimed else { return false }
        isClaimed = true
        return (self.pageIdentity == nil || self.pageIdentity == pageIdentity)
            && (self.style == nil || self.style == style)
    }
}
