import SwiftUI
import UIKit

/// The home title follows the system face used by the surrounding interface.
enum ReadingDeskTitleTypography {
    /// Callers supply a Dynamic Type scaled size; avoid scaling twice.
    static func font(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }
}

/// Extra raster headroom for the jacket's gentle perspective and cover crop.
enum ReadingDeskCoverRaster {
    static func maximumPixelSize(points: CGFloat, scale: CGFloat) -> CGFloat {
        min(896, ceil(points * max(scale, 1) * 1.20))
    }
}
