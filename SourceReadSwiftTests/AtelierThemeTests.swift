import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

final class AtelierThemeTests: XCTestCase {
    func testAtelierPigmentsMatchTheSevenReferencePairsWithoutMixingThemes() throws {
        let referencePairs: [(AppVisualTheme, UInt32, UInt32)] = [
            (.berryLake, 0x65020A, 0x18D5E7),
            (.blushInk, 0xFF7CA2, 0x000000),
            (.periwinkleCocoa, 0x7B88D7, 0x6D483B),
            (.peachMoss, 0xFACBC6, 0x465C47),
            (.inkViolet, 0x0B0C10, 0xA855F7),
            (.pineMist, 0x3A6341, 0xE8E8E4),
            (.kleinSage, 0x012696, 0xA4E2C6)
        ]
        XCTAssertEqual(AppVisualTheme.atelierThemes, referencePairs.map { $0.0 })
        for (theme, primary, secondary) in referencePairs {
            let palette = try XCTUnwrap(theme.atelierPalette)
            XCTAssertEqual(palette.primaryHex, primary, theme.title)
            XCTAssertEqual(palette.secondaryHex, secondary, theme.title)
            if theme == .inkViolet {
                XCTAssertEqual(palette.emphasisFillHex, 0xB873F8, "Star-violet controls need pressed-state contrast headroom")
                XCTAssertEqual(palette.emphasisInkHex, primary)
            } else {
                XCTAssertTrue([primary, secondary].contains(palette.emphasisFillHex), theme.title)
            }
            XCTAssertGreaterThanOrEqual(contrast(palette.emphasisInkHex, palette.emphasisFillHex), 4.5, theme.title)
        }
        for theme in AppVisualTheme.allCases where !theme.isAtelier {
            XCTAssertNil(theme.atelierPalette, "Existing themes keep their own palettes")
        }
    }

    func testAdditionalAtelierThemesKeepDistinctCompositionsAndStoredIdentities() {
        let additions: [(AppVisualTheme, AppVisualTheme.HomeComposition, String)] = [
            (.inkViolet, .index, "inkViolet"), (.pineMist, .gallery, "pineMist"), (.kleinSage, .editorial, "kleinSage")
        ]
        for (theme, composition, identity) in additions {
            XCTAssertEqual(theme.homeComposition, composition)
            XCTAssertEqual(theme.rawValue, identity)
            XCTAssertEqual(theme.preferenceKey("accent"), "settings.visualTheme.\(identity).accentHex")
            XCTAssertEqual(AppVisualTheme.classicDeskThemes.filter { $0 == theme }.count, 1)
            XCTAssertFalse(AppThemeOrnament.hasArtwork(theme: theme, isCard: true))
            XCTAssertFalse(AppThemeOrnament.hasArtwork(theme: theme, isCard: false))
            XCTAssertFalse(theme.supportsLiveGlass)
        }
    }

    func testBothAtelierAccentsRemainReadableOnPaperAndCardsInBothAppearances() {
        for theme in AppVisualTheme.atelierThemes {
            for (inks, papers) in [([theme.accentHex, theme.secondaryHex], [theme.backgroundHex, theme.cardHex]),
                                   ([theme.darkAccentHex, theme.darkSecondaryHex], [theme.darkBackgroundHex, theme.darkCardHex])] {
                for ink in inks {
                    for paper in papers {
                        XCTAssertGreaterThanOrEqual(contrast(ink, paper), 4.5, theme.title)
                    }
                }
            }
        }
    }

    @MainActor func testProminentControlsResolveToReadableReferenceColoursInBothAppearances() {
        let defaults = UserDefaults.standard, key = AppVisualTheme.selectionKey
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        for theme in AppVisualTheme.allCases {
            defaults.set(theme.rawValue, forKey: key)
            for style in [UIUserInterfaceStyle.light, .dark] {
                let traits = UITraitCollection(userInterfaceStyle: style)
                let fill = resolvedHex(AppTheme.prominentFill, traits: traits)
                let ink = resolvedHex(AppTheme.prominentInk, traits: traits)
                if let palette = theme.atelierPalette {
                    XCTAssertEqual(fill, palette.emphasisFillHex, theme.title)
                    XCTAssertEqual(ink, palette.emphasisInkHex, theme.title)
                    XCTAssertGreaterThanOrEqual(contrast(ink, fill), 4.5, theme.title)
                    if style == .dark {
                        XCTAssertGreaterThanOrEqual(contrast(fill, theme.darkCardHex), 3, theme.title)
                    }
                } else {
                    XCTAssertEqual(fill, resolvedHex(AppTheme.accent, traits: traits), theme.title)
                    XCTAssertEqual(ink, 0xFFFFFF, theme.title)
                }
            }
        }
    }

    func testPressedProminentControlsKeepReadableTextOverEveryThemeSurface() throws {
        // AppPressStyle and BookOpenPressStyle dim the entire control while pressed.
        let pressedOpacities = [0.84, 0.88]
        for theme in AppVisualTheme.atelierThemes {
            let palette = try XCTUnwrap(theme.atelierPalette)
            for paper in [theme.backgroundHex, theme.cardHex, theme.darkBackgroundHex, theme.darkCardHex] {
                for opacity in pressedOpacities {
                    let fill = blend(palette.emphasisFillHex, over: paper, opacity: opacity)
                    let ink = blend(palette.emphasisInkHex, over: paper, opacity: opacity)
                    XCTAssertGreaterThanOrEqual(contrast(ink, fill), 4.5, theme.title)
                }
            }
            for opacity in [0.80, 0.85] {
                let ink = blend(palette.emphasisInkHex, over: palette.emphasisFillHex, opacity: opacity)
                XCTAssertGreaterThanOrEqual(contrast(ink, palette.emphasisFillHex), 4.5, theme.title)
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

    private func contrast(_ foreground: UInt32, _ background: UInt32) -> Double {
        let a = luminance(foreground), b = luminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func blend(_ foreground: UInt32, over background: UInt32, opacity: Double) -> UInt32 {
        let channels = [16, 8, 0].map { shift -> UInt32 in
            let front = Double((foreground >> shift) & 255), back = Double((background >> shift) & 255)
            return UInt32((front * opacity + back * (1 - opacity)).rounded())
        }
        return (channels[0] << 16) | (channels[1] << 8) | channels[2]
    }

    @MainActor private func resolvedHex(_ color: Color, traits: UITraitCollection) -> UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        let isRGB = UIColor(color).resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertTrue(isRGB)
        XCTAssertEqual(alpha, 1, accuracy: 0.0001, "Control colours must stay opaque in either appearance")
        let redByte = UInt32((red * 255).rounded()), greenByte = UInt32((green * 255).rounded())
        let blueByte = UInt32((blue * 255).rounded())
        return (redByte << 16) | (greenByte << 8) | blueByte
    }

    private func luminance(_ hex: UInt32) -> Double {
        let components = [16, 8, 0].map { shift -> Double in
            let channel = Double((hex >> shift) & 255) / 255
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
    }
}
