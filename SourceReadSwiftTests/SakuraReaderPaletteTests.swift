import XCTest
@testable import SourceReadSwift

/// 校验 Sakura CSS 主题与原生 ReaderBackground 调色板不漂移。
final class SakuraReaderPaletteTests: XCTestCase {

    private struct BodyPalette: Equatable {
        let background: UInt32
        let text: UInt32
    }

    private func parseBodyPalette(from css: String) -> BodyPalette? {
        let pattern = #"body\s*\{([^}]*background-color[^}]*)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = css as NSString
        guard let match = regex.firstMatch(in: css, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        let body = ns.substring(with: match.range(at: 1))

        func value(for property: String) -> String? {
            for declaration in body.split(separator: ";") {
                let parts = declaration.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                guard key == property else { continue }
                return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }

        guard let background = value(for: "background-color").flatMap(Self.hex),
              let text = value(for: "color").flatMap(Self.hex) else {
            return nil
        }
        return BodyPalette(background: background, text: text)
    }

    /// 支持 #rrggbb 与 rgba(r, g, b, a)；rgba 按白色底合成。
    private static func hex(from value: String) -> UInt32? {
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowered.hasPrefix("#"), lowered.count == 7 {
            return UInt32(lowered.dropFirst(), radix: 16)
        }
        if lowered.hasPrefix("rgba("), lowered.hasSuffix(")") {
            let inner = lowered.dropFirst(5).dropLast(1)
            let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 4,
                  let red = Double(parts[0]),
                  let green = Double(parts[1]),
                  let blue = Double(parts[2]),
                  let alpha = Double(parts[3]) else { return nil }
            func composite(_ channel: Double) -> UInt32 {
                UInt32((channel * alpha + 255.0 * (1.0 - alpha)).rounded())
            }
            return (composite(red) << 16) | (composite(green) << 8) | composite(blue)
        }
        return nil
    }

    func testEverySakuraThemeMapsToMatchingNativePalette() {
        for theme in SakuraThemeCatalog.Theme.allCases {
            let background = ReaderBackground(sakuraTheme: theme)
            XCTAssertEqual(background.sakuraTheme, theme, "round-trip mapping failed for \(theme.rawValue)")

            guard let palette = parseBodyPalette(from: SakuraThemeCatalog.css(for: theme)) else {
                XCTFail("unable to parse body palette from CSS for \(theme.rawValue)")
                continue
            }
            XCTAssertEqual(background.dayBackgroundHex, palette.background,
                           "background drift for \(theme.rawValue)")
            XCTAssertEqual(background.dayTextHex, palette.text,
                           "text drift for \(theme.rawValue)")
        }
    }

    func testSakuraPaletteKnownValues() {
        XCTAssertEqual(ReaderBackground.sakuraClassic.dayBackgroundHex, 0xF9F9F9)
        XCTAssertEqual(ReaderBackground.sakuraClassic.dayTextHex, 0x4A4A4A)
        XCTAssertEqual(ReaderBackground.sakuraDark.dayBackgroundHex, 0x222222)
        XCTAssertEqual(ReaderBackground.sakuraDark.dayTextHex, 0xC9C9C9)
        XCTAssertEqual(ReaderBackground.sakuraSolarized.dayBackgroundHex, 0x002B36)
        XCTAssertEqual(ReaderBackground.sakuraSolarized.dayTextHex, 0x839496)
        XCTAssertEqual(ReaderBackground.sakuraEarthly.dayBackgroundHex, 0xFFFFFF)
        XCTAssertEqual(ReaderBackground.sakuraEarthly.dayTextHex, 0x222222)
        XCTAssertEqual(ReaderBackground.sakuraInk.dayBackgroundHex, 0xFFFFFF)
        XCTAssertEqual(ReaderBackground.sakuraInk.dayTextHex, 0x262626)
        XCTAssertEqual(ReaderBackground.sakuraVader.dayBackgroundHex, 0x120C0E)
        XCTAssertEqual(ReaderBackground.sakuraVader.dayTextHex, 0xD9D8DC)
    }

    func testSakuraNightPalettesRemainReadable() {
        let sakuraCases: [ReaderBackground] = [
            .sakuraClassic, .sakuraDark, .sakuraSolarized,
            .sakuraEarthly, .sakuraInk, .sakuraVader
        ]
        for background in sakuraCases {
            XCTAssertNotEqual(background.nightBackgroundHex, background.nightTextHex,
                              "\(background.rawValue) night palette has zero contrast")
        }
        // 深色主题昼夜同色，浅色主题必须有暗色变体。
        XCTAssertEqual(ReaderBackground.sakuraDark.nightBackgroundHex,
                       ReaderBackground.sakuraDark.dayBackgroundHex)
        XCTAssertEqual(ReaderBackground.sakuraSolarized.nightBackgroundHex,
                       ReaderBackground.sakuraSolarized.dayBackgroundHex)
        XCTAssertEqual(ReaderBackground.sakuraVader.nightBackgroundHex,
                       ReaderBackground.sakuraVader.dayBackgroundHex)
        XCTAssertNotEqual(ReaderBackground.sakuraClassic.nightBackgroundHex,
                          ReaderBackground.sakuraClassic.dayBackgroundHex)
    }

    func testSakuraStatusBarIconPolicy() {
        XCTAssertTrue(ReaderBackground.sakuraClassic.darkStatusIcon(isNight: false))
        XCTAssertTrue(ReaderBackground.sakuraEarthly.darkStatusIcon(isNight: false))
        XCTAssertTrue(ReaderBackground.sakuraInk.darkStatusIcon(isNight: false))
        XCTAssertFalse(ReaderBackground.sakuraDark.darkStatusIcon(isNight: false))
        XCTAssertFalse(ReaderBackground.sakuraSolarized.darkStatusIcon(isNight: false))
        XCTAssertFalse(ReaderBackground.sakuraVader.darkStatusIcon(isNight: false))
        for background in ReaderBackground.allCases {
            XCTAssertFalse(background.darkStatusIcon(isNight: true))
        }
    }

    func testSakuraCasesAreCodableRoundTrip() throws {
        let cases: [ReaderBackground] = [
            .sakuraClassic, .sakuraDark, .sakuraSolarized,
            .sakuraEarthly, .sakuraInk, .sakuraVader
        ]
        let data = try JSONEncoder().encode(cases)
        let decoded = try JSONDecoder().decode([ReaderBackground].self, from: data)
        XCTAssertEqual(decoded, cases)
        XCTAssertEqual(Set(cases.map(\.rawValue)).count, 6)
    }

    func testNonSakuraPalettesHaveNoSakuraMapping() {
        XCTAssertNil(ReaderBackground.paper.sakuraTheme)
        XCTAssertNil(ReaderBackground.custom.sakuraTheme)
        XCTAssertEqual(ReaderBackground.allCases.count, 16)
    }
}
