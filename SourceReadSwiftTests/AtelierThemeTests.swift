import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

final class AtelierThemeTests: XCTestCase {
    func testBothAtelierAccentsRemainReadableOnPaperAndCardsInBothAppearances() {
        for theme in AppVisualTheme.atelierThemes {
            for (inks, papers) in [([theme.accentHex, theme.secondaryHex], [theme.backgroundHex, theme.cardHex]),
                                   ([theme.darkAccentHex, theme.darkSecondaryHex], [theme.darkBackgroundHex, theme.darkCardHex])] {
                for ink in inks {
                    for paper in papers {
                        let a = luminance(ink), b = luminance(paper)
                        XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5, theme.title)
                    }
                }
            }
        }
    }

    @MainActor func testBrandAssetDecodesAtSmallPresentationSize() throws {
        let image = try XCTUnwrap(UIImage(named: "BrandMark"))
        XCTAssertEqual(image.size, CGSize(width: 192, height: 192))
        XCTAssertNotNil(image.cgImage)
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        XCTAssertNotNil(rendered.cgImage)
    }

    func testEditorialCutDoesNotTurnCircularControlsIntoSquareCards() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let card = AppThemeCardShape(theme: .berryLake, radius: 4).path(in: rect)
        XCTAssertFalse(card.contains(CGPoint(x: 99, y: 1)))
        XCTAssertTrue(card.contains(CGPoint(x: 2, y: 2)))
        let control = AppThemeCardShape(theme: .berryLake, radius: 999).path(in: rect)
        XCTAssertFalse(control.contains(CGPoint(x: 2, y: 2)))
        XCTAssertTrue(control.contains(CGPoint(x: 50, y: 50)))
    }

    private func luminance(_ hex: UInt32) -> Double {
        let components = [16, 8, 0].map { shift -> Double in
            let channel = Double((hex >> shift) & 255) / 255
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
    }
}
