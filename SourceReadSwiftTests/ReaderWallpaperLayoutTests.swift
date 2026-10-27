import XCTest
import UIKit
@testable import SourceReadSwift

final class ReaderWallpaperLayoutTests: XCTestCase {
    func testDownsampleKeepsAspectRatio() {
        let target = ReaderWallpaperLayoutPolicy.downsampledPixelSize(
            for: CGSize(width: 1080, height: 2160),
            maxPixel: 1080
        )
        XCTAssertEqual(target.width, 540, accuracy: 0.5)
        XCTAssertEqual(target.height, 1080, accuracy: 0.5)
    }

    func testDownsampleDoesNotUpscale() {
        let size = CGSize(width: 390, height: 844)
        XCTAssertEqual(
            ReaderWallpaperLayoutPolicy.downsampledPixelSize(for: size),
            size
        )
    }

    func testDownsampleHandlesZeroSize() {
        XCTAssertEqual(
            ReaderWallpaperLayoutPolicy.downsampledPixelSize(for: .zero),
            .zero
        )
    }

    func testFillModeMapsToUIKitContentMode() {
        XCTAssertEqual(ReaderWallpaperFillMode.fill.uiContentMode, .scaleAspectFill)
        XCTAssertEqual(ReaderWallpaperFillMode.fit.uiContentMode, .scaleAspectFit)
        XCTAssertEqual(ReaderWallpaperFillMode.stretch.uiContentMode, .scaleToFill)
    }
}
