import Foundation

/// Normalized paging policy shared by direct manipulation, buttons and VoiceOver.
enum IntroPaging {
    static let count = 6

    static func clamp(_ proposed: Double) -> Double {
        guard proposed.isFinite else { return 0 }
        return min(max(proposed, 0), Double(count - 1))
    }

    static func position(start: Double, translation: Double, width: Double) -> Double {
        guard width.isFinite, width > 0, translation.isFinite else { return clamp(start) }
        return clamp(start - translation / width)
    }

    static func target(origin: Int, translation: Double, predicted: Double, width: Double) -> Int {
        guard width.isFinite, width > 0, translation.isFinite, predicted.isFinite else { return Int(clamp(Double(origin))) }
        let fraction = -translation / width
        let projection = -predicted / width
        let direction: Int
        if abs(fraction) >= 0.22 { direction = fraction > 0 ? 1 : -1 }
        else if abs(projection) >= 0.45 { direction = projection > 0 ? 1 : -1 }
        else { direction = 0 }
        return Int(clamp(Double(Int(clamp(Double(origin))) + direction)))
    }

    static func blend(_ first: Double, _ second: Double, fraction: Double) -> Double {
        let amount = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        return first + (second - first) * amount
    }
}
