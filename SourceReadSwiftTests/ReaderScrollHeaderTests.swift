import XCTest
import SwiftUI
@testable import SourceReadSwift

final class ReaderScrollHeaderTests: XCTestCase {
    func testDefaultBottomStatusStillShowsChapterHeader() {
        XCTAssertTrue(ReaderScrollChromePolicy.headerVisible(chapterStyle: .header, statusPosition: "bottom"))
        XCTAssertTrue(ReaderScrollChromePolicy.headerVisible(chapterStyle: .inline, statusPosition: "bottom"))
    }

    func testExplicitHiddenHeadingAndTopStatusPreferencesAreRespected() {
        XCTAssertFalse(ReaderScrollChromePolicy.headerVisible(chapterStyle: .hidden, statusPosition: "bottom"))
        XCTAssertTrue(ReaderScrollChromePolicy.headerVisible(chapterStyle: .hidden, statusPosition: "top"))
        XCTAssertTrue(ReaderScrollChromePolicy.headerVisible(chapterStyle: .hidden, statusPosition: "both"))
    }

    func testBodyStartsAfterFixedHeaderAcrossSafeAreas() {
        for top: CGFloat in [0, 20, 47, 59] {
            let geometry = ReaderScrollChromeGeometry(safeTop: top, headerVisible: true, showSystemStatusBar: false)
            XCTAssertEqual(geometry.headerTop, top + 2)
            XCTAssertEqual(geometry.protectedHeight, geometry.headerTop + 22 + 6)
        }
    }

    func testStatusBarFallbackDoesNotLeaveClockOnScrollingBody() {
        let geometry = ReaderScrollChromeGeometry(safeTop: 0, headerVisible: true, showSystemStatusBar: true)
        XCTAssertEqual(geometry.headerTop, 22)
        XCTAssertEqual(geometry.protectedHeight, 50)
    }

    func testInvalidSafeAreasCannotProduceInvalidFrames() {
        for top: CGFloat in [-20, .nan, .infinity] {
            let geometry = ReaderScrollChromeGeometry(safeTop: top, headerVisible: true, showSystemStatusBar: false)
            XCTAssertEqual(geometry.protectedHeight, 30)
        }
    }

    @MainActor func testPaperBandRendersIdenticallyAboveDifferentBodyLayers() throws {
        let geometry = ReaderScrollChromeGeometry(safeTop: 59, headerVisible: true, showSystemStatusBar: false)
        @MainActor func pixels(underlay: Color) throws -> Data {
            let renderer = ImageRenderer(content:
                ZStack(alignment: .top) {
                    underlay
                    ReaderScrollChapterHeader(
                        title: "第154章 所有的痛苦都是罪有应得（2合1）",
                        geometry: geometry, horizontalPadding: 20,
                        foreground: .black, paper: Color(red: 0.8, green: 0.85, blue: 0.9)
                    ) { EmptyView() }
                }
                .frame(width: 390, height: geometry.protectedHeight)
            )
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(
                    data: buffer.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue))
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            return Data(bytes)
        }
        XCTAssertEqual(try pixels(underlay: .red), try pixels(underlay: .blue),
                       "The chapter band must fully mask moving body layers, not blend with them")
    }
}
