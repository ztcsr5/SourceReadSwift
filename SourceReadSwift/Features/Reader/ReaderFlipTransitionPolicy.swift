import CoreGraphics
import QuartzCore

/// Pure geometry for the 3D page-flip transition.
///
/// The flip surface reuses the same three-slot paging scroll view as cover
/// mode; only the layer transform differs. Keeping the mapping in a pure
/// type keeps it testable without a simulator.
enum ReaderFlipTransitionPolicy {
    /// Rotation applied to the turning page, in radians, for a drag
    /// progress in `0...1`. Negative values turn the page towards the
    /// spine on the left edge.
    static func rotationAngle(progress: CGFloat) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        return -clamped * (CGFloat.pi / 2)
    }

    /// Perspective depth. A larger denominator flattens the page.
    static func perspectiveTransform(depth: CGFloat = 900) -> CATransform3D {
        var transform = CATransform3DIdentity
        transform.m34 = -1 / max(depth, 1)
        return transform
    }

    /// Opacity of the shadow the turning page casts on the page below.
    static func shadowOpacity(progress: CGFloat) -> Float {
        let clamped = min(max(progress, 0), 1)
        return Float(sin(Double(clamped) * .pi / 2)) * 0.6
    }

    /// The turning page darkens slightly as it rotates away from the light.
    static func turningPageBrightness(progress: CGFloat) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        return 1 - clamped * 0.16
    }

    /// True when the drag is far enough for the caller to treat it as a
    /// page turn. Matches the cover surface half-page threshold.
    static func commits(progress: CGFloat) -> Bool {
        abs(progress) >= 0.5
    }
}