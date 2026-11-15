import CoreGraphics
import Foundation

/// Geometry and bounded release timing for the opt-in reader transition.
/// The system edge-pop animator does not use these values.
enum ReaderSlideMotion {
    static let layeredDuration: TimeInterval = 0.35

    static func backPlaneTravel(width: CGFloat) -> CGFloat {
        min(max(width, 0) * 0.16, 64)
    }

    /// Slow a long fast-throw enough to stay perceptible, but do not linger
    /// when the finger has already dragged almost to its endpoint.
    static func completionSpeed(progress: CGFloat, velocity: CGFloat, width: CGFloat,
                                isFinishing: Bool) -> CGFloat {
        let progress = min(max(progress, 0), 1)
        let remaining = isFinishing ? 1 - progress : progress
        let unscaledDuration = remaining * CGFloat(layeredDuration)
        let screenSpeed = min(4, max(0, velocity / max(1, width)))
        let minimum: CGFloat = isFinishing ? 0.14 : 0.115
        let natural = isFinishing ? unscaledDuration / (1 + screenSpeed * 0.17) : unscaledDuration * 0.92
        let settledDuration = min(0.32, max(minimum, natural))
        return min(1.45, max(0.36, unscaledDuration / settledDuration))
    }
}
