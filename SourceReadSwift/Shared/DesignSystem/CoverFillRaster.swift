import Foundation

/// Enough pixels on the cropped short side of an enlarged jacket, without upsampling the original.
struct CoverFillRaster: Sendable {
    private static let decodeCeiling: CGFloat = 1_024
    private static let cropHeadroom: CGFloat = 1.20
    private let widthPixels: Int
    private let heightPixels: Int

    init?(width: CGFloat, height: CGFloat, displayScale: CGFloat) {
        let scale = max(displayScale, 1) * Self.cropHeadroom
        let width = width * scale
        let height = height * scale
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        widthPixels = Int(ceil(min(width, Self.decodeCeiling)))
        heightPixels = Int(ceil(min(height, Self.decodeCeiling)))
    }

    var cacheSize: String { "fill\(widthPixels)x\(heightPixels)" }

    /// Resolve against the oriented original, not a previously downsampled shelf cell.
    func maximumPixelSize(orientedWidth: CGFloat, orientedHeight: CGFloat) -> CGFloat {
        guard orientedWidth.isFinite, orientedHeight.isFinite, orientedWidth > 0, orientedHeight > 0 else {
            return CGFloat(max(widthPixels, heightPixels))
        }
        let fillScale = min(1, max(CGFloat(widthPixels) / orientedWidth, CGFloat(heightPixels) / orientedHeight))
        return min(Self.decodeCeiling, ceil(max(orientedWidth, orientedHeight) * fillScale))
    }
}
