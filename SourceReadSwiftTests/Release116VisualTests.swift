import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

final class Release116VisualTests: XCTestCase {
    func testThemesChangeGeometryTypographyAndSurfaceNotOnlyAccent() {
        XCTAssertEqual(AppVisualTheme.allCases.count, 6)
        XCTAssertEqual(Set(AppVisualTheme.allCases.map(\.radius)).count, 6)
        XCTAssertEqual(Set(AppVisualTheme.allCases.map(\.backgroundHex)).count, 6)
        XCTAssertEqual(AppVisualTheme.classic.preferenceKey("accent"), "settings.accentHex")
        XCTAssertNotEqual(AppVisualTheme.coast.preferenceKey("accent"), AppVisualTheme.rose.preferenceKey("accent"))
        XCTAssertEqual(AppVisualTheme.editorial.borderWidth, 1)
        XCTAssertEqual(AppVisualTheme.graphite.borderWidth, 1)
    }

    func testNewThemeDefaultAccentContrastInBothAppearances() {
        func luminance(_ rgb: UInt32) -> Double {
            let components = [16,8,0].map { shift -> Double in
                let value = Double((rgb >> shift) & 255) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
        }
        for theme in AppVisualTheme.allCases where theme != .classic {
            for (foreground, background) in [(theme.accentHex,theme.cardHex), (theme.darkAccentHex,theme.darkCardHex)] {
                let a = luminance(foreground), b = luminance(background)
                XCTAssertGreaterThanOrEqual((max(a,b) + 0.05) / (min(a,b) + 0.05), 4.5, theme.title)
            }
        }
    }

    @MainActor func testThemePersistenceAndBackup() {
        let defaults = UserDefaults.standard
        let keys = ["settings.visualTheme", AppVisualTheme.coast.preferenceKey("accent")]
        let old = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, old) { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
        defaults.set("not-a-theme", forKey: keys[0])
        XCTAssertEqual(AppVisualTheme.current, .classic)
        defaults.set("coast", forKey: keys[0]); defaults.set("123456", forKey: keys[1])
        XCTAssertEqual(AppVisualTheme.current, .coast)
        let backup = AppState().makeAppDataBackupSnapshot()
        XCTAssertNotNil(backup.readerPreferences[keys[0]])
        XCTAssertNotNil(backup.readerPreferences[keys[1]])
    }

    func testFourOriginalWallpapersDecodeAndEnterCache() async throws {
        for name in ["ReadingBamboo", "ReadingMountains", "ReadingGinkgo", "ReadingTide"] {
            let image = await ReaderIllustratedBackgroundStore.load(name)
            let decoded = try XCTUnwrap(image, "Missing asset: \(name)")
            XCTAssertGreaterThan(decoded.size.height, decoded.size.width)
            XCTAssertNotNil(ReaderIllustratedBackgroundStore.cached(name))
        }
    }

    @MainActor func testThemeAndLegacyChromeRenderEvidence() async throws {
        let defaults = UserDefaults.standard
        let old = defaults.object(forKey: "settings.visualTheme")
        defer { if let old { defaults.set(old, forKey: "settings.visualTheme") } else { defaults.removeObject(forKey: "settings.visualTheme") } }
        for theme in AppVisualTheme.allCases {
            defaults.set(theme.rawValue, forKey: "settings.visualTheme")
            for style in [UIUserInterfaceStyle.light, .dark] {
                try await snapshot("theme-\(theme.rawValue)-\(style == .dark ? "dark" : "light")", width: 390, height: 600, style: style) {
                    VStack(spacing: 16) {
                        HStack { PaperBetweenMark(); Text(theme.title).font(.title2); Spacer() }
                        VStack(alignment: .leading, spacing: 12) {
                            Label("继续阅读", systemImage: theme.ornament).font(.headline)
                            Text("字里行间，留一点安静。\n主题同步纸面、卡片、字体与边框。")
                            HStack { Text("阅读记录"); Spacer(); Text("今日 32 分钟").foregroundStyle(AppTheme.accent) }
                        }.frame(maxWidth: .infinity, alignment: .leading).podcastCard()
                        Spacer()
                        LegacyTabBar(selection: .constant(0), onSearch: {})
                    }.padding(16).font(.system(.body, design: theme.fontDesign)).background(AppTheme.background)
                }
            }
        }
        try await snapshot("legacy-tab-320", width: 320, height: 110) {
            LegacyTabBar(selection: .constant(1), onSearch: {}).background(AppTheme.background)
        }
    }

    @MainActor func testReaderOpaqueTopAndWallpaperRenderEvidence() async throws {
        let defaults = UserDefaults.standard
        let keys = ["reader.background", "reader.mode"]
        let old = keys.map { defaults.object(forKey: $0) }
        defer { for (key,value) in zip(keys,old) { if let value { defaults.set(value,forKey:key) } else { defaults.removeObject(forKey:key) } } }
        defaults.set("scroll", forKey: "reader.mode")
        let chapter = BookChapter(title: "测试章节 · 顶部遮挡", url: "https://fixture.example/1", bookUrl: "fixture", index: 0, isVip: false)
        let content = ChapterContent(chapter: chapter, title: chapter.title, paragraphs: Array(repeating: "这是顶部与安全区域的遮挡检查。正文不应透过菜单顶部；阅读背景应保持清晰而安静。", count: 20), nextContentUrl: nil)
        let app = AppState()
        for background in ["white", "bamboo"] {
            defaults.set(background, forKey: keys[0])
            if background == "bamboo" { _ = await ReaderIllustratedBackgroundStore.load("ReadingBamboo") }
            try await snapshot("reader-top-\(background)", width: 390, height: 844) {
                ReaderView(bookID: "", content: content, chapterIndex: 0, totalChapters: 1, initialOverlayVisible: true).environmentObject(app)
            }
        }
    }

    @MainActor private func snapshot<V: View>(_ name: String, width: CGFloat, height: CGFloat, style: UIUserInterfaceStyle = .light, @ViewBuilder content: () -> V) async throws {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = UIScreen.main.bounds
        window.overrideUserInterfaceStyle = style
        let container = UIViewController()
        container.overrideUserInterfaceStyle = style
        let host = UIHostingController(rootView: content().preferredColorScheme(style == .dark ? .dark : .light))
        host.overrideUserInterfaceStyle = style
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.addChild(host); container.view.addSubview(host.view)
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: height); host.didMove(toParent: container)
        defer { window.isHidden = true }
        try await Task.sleep(nanoseconds: 500_000_000)
        host.view.layoutIfNeeded()
        XCTAssertEqual(host.view.bounds.width, width, accuracy: 1)
        XCTAssertEqual(host.traitCollection.userInterfaceStyle, style, "Rendered evidence must receive its named appearance")
        let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "release116-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
