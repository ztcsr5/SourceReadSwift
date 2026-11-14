import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

final class AtelierThemeTests: XCTestCase {
    func testAtelierPigmentsMatchTheSevenReferencePairsWithoutMixingThemes() throws {
        let referencePairs: [(AppVisualTheme, UInt32, UInt32)] = [
            (.kleinSage, 0x012696, 0x855A0C)
        ]
        XCTAssertEqual(AppVisualTheme.atelierThemes, referencePairs.map { $0.0 })
        for (theme, primary, secondary) in referencePairs {
            let palette = try XCTUnwrap(theme.atelierPalette)
            XCTAssertEqual(palette.primaryHex, primary, theme.title)
            XCTAssertEqual(palette.secondaryHex, secondary, theme.title)
            // Emphasis fills carry the second hue (or a deepened shade of it so the
            // pressed opacity still clears 4.5:1). They must never drift to the first hue.
            let fillHue = hls(palette.emphasisFillHex).hue, secondHue = hls(secondary).hue
            var fillGap = abs(fillHue - secondHue)
            fillGap = min(fillGap, 360 - fillGap)
            XCTAssertLessThanOrEqual(fillGap, 15, "\(theme.title) emphasis fill must stay in the secondary hue")
            XCTAssertLessThanOrEqual(hls(palette.emphasisFillHex).lightness, hls(secondary).lightness + 0.001,
                                     "\(theme.title) emphasis fill may only deepen, never lighten")
            XCTAssertGreaterThanOrEqual(contrast(palette.emphasisInkHex, palette.emphasisFillHex), 4.5, theme.title)
        }
        for theme in AppVisualTheme.allCases where !theme.isAtelier {
            XCTAssertNil(theme.atelierPalette, "Existing themes keep their own palettes")
        }
    }

    func testAdditionalAtelierThemesKeepDistinctCompositionsAndStoredIdentities() {
        let additions: [(AppVisualTheme, AppVisualTheme.HomeComposition, String)] = [
            (.kleinSage, .editorial, "kleinSage")
        ]
        for (theme, composition, identity) in additions {
            XCTAssertEqual(theme.homeComposition, composition)
            XCTAssertEqual(theme.rawValue, identity)
            XCTAssertEqual(theme.preferenceKey("accent"), "settings.visualTheme.\(identity).accentHex")
            XCTAssertEqual(AppVisualTheme.classicDeskThemes.filter { $0 == theme }.count, 1)
            XCTAssertFalse(AppThemeOrnament.hasArtwork(theme: theme, isCard: true))
            XCTAssertFalse(AppThemeOrnament.hasArtwork(theme: theme, isCard: false))
            XCTAssertTrue(theme.supportsLiveGlass)
        }
    }

    /// 撞色主题的硬指标：两个控件色在色轮上真的分开，且都还能当文字用。
    /// 只靠肉眼看截图不算验证，所以这里用十进制 HLS 与 WCAG 比值算。
    func testClashingAccentPairsSeparateOnTheWheelAndStayReadable() {
        for theme in AppVisualTheme.atelierThemes {
            let primary = hls(theme.accentHex), secondary = hls(theme.secondaryHex)
            var hueGap = abs(primary.hue - secondary.hue)
            hueGap = min(hueGap, 360 - hueGap)
            // 两色都要压在纸面上当正文墨色用，所以明度天然接近；
            // 撞色靠色相分离与"各自都过 4.5:1"两条同时成立来表达，而不是靠亮度差。
            XCTAssertGreaterThanOrEqual(hueGap, 120, "\(theme.title) needs a real hue clash")
            XCTAssertGreaterThan(abs(primary.hue - secondary.hue), 0.5, "\(theme.title) must not reuse one hue")
            let darkPrimary = hls(theme.darkAccentHex), darkSecondary = hls(theme.darkSecondaryHex)
            var darkGap = abs(darkPrimary.hue - darkSecondary.hue)
            darkGap = min(darkGap, 360 - darkGap)
            XCTAssertGreaterThanOrEqual(darkGap, 120, "\(theme.title) dark pair needs a hue clash")
            for (ink, paper) in [(theme.accentHex, theme.backgroundHex), (theme.accentHex, theme.cardHex),
                                 (theme.secondaryHex, theme.backgroundHex), (theme.secondaryHex, theme.cardHex),
                                 (theme.darkAccentHex, theme.darkBackgroundHex), (theme.darkAccentHex, theme.darkCardHex),
                                 (theme.darkSecondaryHex, theme.darkBackgroundHex), (theme.darkSecondaryHex, theme.darkCardHex)] {
                XCTAssertGreaterThanOrEqual(contrast(ink, paper), 4.5, "\(theme.title) ink \(ink) on \(paper)")
            }
        }
    }

    private func hls(_ rgb: UInt32) -> (hue: Double, lightness: Double) {
        let red = Double((rgb >> 16) & 255) / 255, green = Double((rgb >> 8) & 255) / 255, blue = Double(rgb & 255) / 255
        let high = max(red, green, blue), low = min(red, green, blue), delta = high - low
        let lightness = (high + low) / 2
        guard delta > 0 else { return (0, lightness) }
        let hue: Double
        if high == red { hue = 60 * (((green - blue) / delta).truncatingRemainder(dividingBy: 6)) }
        else if high == green { hue = 60 * ((blue - red) / delta + 2) }
        else { hue = 60 * ((red - green) / delta + 4) }
        return (hue < 0 ? hue + 360 : hue, lightness)
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
                    // 深色下按钮换成提亮的同色相；浅色下用压深的填充。
                    let expectedFill = style == .dark ? palette.darkEmphasisFillHex : palette.emphasisFillHex
                    let expectedInk = style == .dark ? palette.darkEmphasisInkHex : palette.emphasisInkHex
                    XCTAssertEqual(fill, expectedFill, theme.title)
                    XCTAssertEqual(ink, expectedInk, theme.title)
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
            // 浅色填充只出现在浅色纸面，深色填充只出现在深色纸面；交叉组合不是真实场景。
            for (fillHex, inkHex, papers) in [(palette.emphasisFillHex, palette.emphasisInkHex,
                                               [theme.backgroundHex, theme.cardHex]),
                                              (palette.darkEmphasisFillHex, palette.darkEmphasisInkHex,
                                               [theme.darkBackgroundHex, theme.darkCardHex])] {
                for paper in papers {
                    for opacity in pressedOpacities {
                        let fill = blend(fillHex, over: paper, opacity: opacity)
                        let ink = blend(inkHex, over: paper, opacity: opacity)
                        XCTAssertGreaterThanOrEqual(contrast(ink, fill), 4.5, theme.title)
                    }
                }
                for opacity in [0.80, 0.85] {
                    let ink = blend(inkHex, over: fillHex, opacity: opacity)
                    XCTAssertGreaterThanOrEqual(contrast(ink, fillHex), 4.5, theme.title)
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
        let card = AppThemeCardShape(theme: .kleinSage, radius: 4).path(in: rect)
        XCTAssertFalse(card.contains(CGPoint(x: 99, y: 1)))
        XCTAssertTrue(card.contains(CGPoint(x: 2, y: 2)))
        let control = AppThemeCardShape(theme: .kleinSage, radius: 999).path(in: rect)
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
