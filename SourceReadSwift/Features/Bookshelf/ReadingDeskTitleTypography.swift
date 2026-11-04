import SwiftUI
import UIKit

/// Scoped to the home reading title, never applied to metadata or reader text.
enum ReadingDeskTitleTypography {
    static let fallbackPostScriptName = "ReadingDeskSong-Regular"
    private static let systemCandidates = ["STSongti-SC-Regular", "SongtiSC-Regular", "Songti SC Regular"]
    static let postScriptName = (systemCandidates + [fallbackPostScriptName])
        .lazy.compactMap { UIFont(name: $0, size: 24)?.fontName }
        .first

    /// Callers supply a Dynamic Type scaled size; avoid scaling twice.
    static func font(size: CGFloat) -> Font {
        if let postScriptName { return .custom(postScriptName, fixedSize: size) }
        return .system(size: size, weight: .regular, design: .serif)
    }
}

/// Extra raster headroom for the jacket's gentle perspective and cover crop.
enum ReadingDeskCoverRaster {
    static func maximumPixelSize(points: CGFloat, scale: CGFloat) -> CGFloat {
        min(896, ceil(points * max(scale, 1) * 1.20))
    }
}
