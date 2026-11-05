import SwiftUI
import XCTest
@testable import SourceReadSwift

final class Release117AppearanceTests: XCTestCase {
    func testThemesWithoutOrnamentsDoNotCreateEmptyCanvasLayers() {
        for theme in AppVisualTheme.allCases {
            XCTAssertEqual(AppThemeOrnament.hasArtwork(theme: theme, isCard: true),
                           [.folio, .blueprint].contains(theme))
            XCTAssertEqual(AppThemeOrnament.hasArtwork(theme: theme, isCard: false),
                           [.folio, .blueprint, .inkwash].contains(theme))
        }
    }

    @MainActor func testLivePaletteStillResolvesDefaultDarkCustomAndInvalidAccentColors() {
        let defaults = UserDefaults.standard
        let forestAccent = AppVisualTheme.forest.preferenceKey("accent")
        let classicAccent = AppVisualTheme.classic.preferenceKey("accent")
        let keys = [AppVisualTheme.selectionKey, forestAccent, classicAccent]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        defaults.set(AppVisualTheme.forest.rawValue, forKey: AppVisualTheme.selectionKey)
        defaults.set("INVALID", forKey: forestAccent)
        XCTAssertEqual(AppTheme.accentUIColor.resolvedColor(with: light), AppVisualTheme.uiColor(AppVisualTheme.forest.accentHex))
        XCTAssertEqual(AppTheme.accentUIColor.resolvedColor(with: dark), AppVisualTheme.uiColor(AppVisualTheme.forest.darkAccentHex))
        defaults.set("123456", forKey: forestAccent)
        XCTAssertEqual(AppTheme.accentUIColor.resolvedColor(with: light), AppVisualTheme.uiColor(0x123456))
        XCTAssertEqual(AppTheme.accentUIColor.resolvedColor(with: dark), AppVisualTheme.uiColor(0x123456))
        defaults.set(AppVisualTheme.classic.rawValue, forKey: AppVisualTheme.selectionKey)
        defaults.set(String(format: "%06X", AppVisualTheme.classic.accentHex), forKey: classicAccent)
        XCTAssertEqual(AppTheme.accentUIColor.resolvedColor(with: dark), AppVisualTheme.uiColor(AppVisualTheme.classic.darkAccentHex))
    }

    @MainActor func testSystemModeTracksLiveWindowTraitChanges() async throws {
        try await check(mode: .system, expected: [.light, .dark, .light])
    }

    @MainActor func testExplicitDarkModeStillOverridesSystem() async throws {
        try await check(mode: .dark, expected: [.dark, .dark, .dark])
    }

    @MainActor private func check(mode: ThemeMode, expected: [ColorScheme]) async throws {
        var observed: ColorScheme?
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = UIScreen.main.bounds
        let root = SchemeProbe { observed = $0 }.modifier(AppColorSchemePreference(mode: mode))
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for (index, style) in [UIUserInterfaceStyle.light, .dark, .light].enumerated() {
            window.overrideUserInterfaceStyle = style
            for _ in 0..<30 {
                if observed == expected[index] { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertEqual(observed, expected[index], "Mode \(mode), system trait \(style)")
        }
    }
}

private struct SchemeProbe: View {
    @Environment(\.colorScheme) private var scheme
    let report: (ColorScheme) -> Void
    var body: some View {
        Color.clear.onAppear { report(scheme) }.onChange(of: scheme) { report($0) }
    }
}
