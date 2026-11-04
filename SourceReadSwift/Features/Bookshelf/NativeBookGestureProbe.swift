#if DEBUG
import UIKit

/// Finds navigation gestures without observing the document's own scrolling/selection.
enum NativeBookGestureProbe {
    private static let containerLimit = 256

    static func collect(in root: UIView) -> [UIGestureRecognizer] {
        var pending = [root]
        var cursor = 0
        var gestures: [UIGestureRecognizer] = []
        while cursor < pending.count, cursor < containerLimit {
            let container = pending[cursor]
            cursor += 1
            guard !(container is UIScrollView), !(container is UIControl),
                  container.accessibilityIdentifier != "reader.webScrollSurface" else { continue }
            gestures.append(contentsOf: container.gestureRecognizers ?? [])
            pending.append(contentsOf: container.subviews)
        }
        return gestures.filter {
            !($0 is UITapGestureRecognizer) && !($0 is UILongPressGestureRecognizer)
                && $0.name != "reader.menuSwipeExit"
        }
    }
}
#endif
