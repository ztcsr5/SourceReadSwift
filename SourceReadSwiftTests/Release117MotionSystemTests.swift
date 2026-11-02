import SwiftUI
import XCTest
@testable import SourceReadSwift

final class Release117MotionSystemTests: XCTestCase {
    func testMotionVocabularyHasOneAccessibleOptOut() {
        let normal = AppMotionPolicy(reducesMotion: false), reduced = AppMotionPolicy(reducesMotion: true)
        for event in [AppMotionPolicy.Event.press, .navigation, .expansion, .background, .bookmark] {
            XCTAssertNotNil(normal.animation(event)); XCTAssertNil(reduced.animation(event))
        }
        XCTAssertEqual(normal.duration(.navigation), 0.30)
        XCTAssertEqual(normal.duration(.expansion), 0.44)
        XCTAssertNil(normal.backgroundAnimation(hasPreviousPalette: false, hasNextPalette: true))
        XCTAssertNil(normal.backgroundAnimation(hasPreviousPalette: true, hasNextPalette: false))
        XCTAssertNotNil(normal.backgroundAnimation(hasPreviousPalette: true, hasNextPalette: true))
        XCTAssertNil(reduced.backgroundAnimation(hasPreviousPalette: true, hasNextPalette: true))
    }

    func testHeaderAndChapterNamePreferencesAreBoundedAndIndependent() {
        XCTAssertEqual(ReaderHeadingPreferences.titleSize(custom: 0, body: 20), 26)
        XCTAssertEqual(ReaderHeadingPreferences.titleSize(custom: 32, body: 20), 32)
        XCTAssertEqual(ReaderHeadingPreferences.titleSize(custom: .infinity, body: 20), 26)
        XCTAssertEqual(ReaderHeadingPreferences.headerSize(.nan), 12)
        XCTAssertEqual(ReaderHeadingPreferences.headerSize(99), 18)
        XCTAssertEqual(ReaderHeadingPreferences.headerGap(-100), 0)
        for systemBar in [false, true] {
            XCTAssertEqual(ReaderHeadingPreferences.showsTopStatus(position: "top", systemBar: systemBar, allowsDuplicates: false), !systemBar)
            XCTAssertTrue(ReaderHeadingPreferences.showsTopStatus(position: "both", systemBar: systemBar, allowsDuplicates: true))
            XCTAssertFalse(ReaderHeadingPreferences.showsTopStatus(position: "bottom", systemBar: systemBar, allowsDuplicates: true))
        }
        let size = CGSize(width: 320, height: 568)
        let original = ReaderPageGeometry(viewportSize: size, safeTop: 44, safeBottom: 34, horizontalMargin: 21)
        let custom = ReaderPageGeometry(viewportSize: size, safeTop: 44, safeBottom: 34, horizontalMargin: 21, headerFontSize: 18, headerTopGap: 24)
        XCTAssertEqual(original.bodyTop, 78)
        XCTAssertGreaterThan(custom.bodyTop, original.bodyTop)
        XCTAssertGreaterThanOrEqual(custom.headerRect.height, 21)
        XCTAssertGreaterThan(custom.bodyRect.minY, custom.headerRect.maxY)
        XCTAssertGreaterThan(custom.contentHeight, ReaderPageChrome.minimumBodyHeight)
        let metrics = ReaderPageContainerMetrics(size: size, globalMinY: 0, rootViewportHeight: size.height, rootSafeTop: 44, rootSafeBottom: 34)
        XCTAssertEqual(metrics.geometry(horizontalMargin: 21, chromeLayout: .header, contentExtendsIntoChrome: false,
                                        headerFontSize: 18, headerTopGap: 24), custom,
                       "Measured and fallback page geometry must reserve the same custom header")
        let scroll = ReaderScrollChromeGeometry(safeTop: 44, headerVisible: true, showSystemStatusBar: true, fontSize: 18, topGap: 24)
        XCTAssertGreaterThanOrEqual(scroll.protectedHeight, scroll.headerTop + 24)
    }

    func testNewThemesPreserveOldIDsAndIntroduceDistinctStructures() {
        XCTAssertEqual(Set(AppVisualTheme.allCases.map(\.rawValue)), Set(["classic", "botanical", "editorial", "coast", "rose", "graphite", "folio", "inkwash", "blueprint"]))
        XCTAssertNotEqual(AppVisualTheme.folio.radius, AppVisualTheme.inkwash.radius)
        XCTAssertNotEqual(AppVisualTheme.folio.ornament, AppVisualTheme.blueprint.ornament)
        XCTAssertEqual(AppVisualTheme.classic.preferenceKey("accent"), "settings.accentHex")
        XCTAssertNotEqual(AppVisualTheme.folio.preferenceKey("accent"), AppVisualTheme.editorial.preferenceKey("accent"))
    }

    func testWebChapterTitleStyleDoesNotChangeBodyTypography() {
        var style = WebReaderStylePayload.make(fontFamily: .system, fontSize: 20, lineSpacing: 8,
            pagePadding: 21, letterSpacing: 0, paragraphSpacing: 16, paragraphIndent: 40,
            titleSpacing: 12, footerHeight: 72, topInset: 80, textColor: .black,
            surfaceColor: .white, highlightColor: .yellow, accentColor: .blue, selectable: true)
        style.applyChapterHeading(size: 34, family: .maShanZheng, isBold: false, bodyFamily: .system)
        XCTAssertEqual(style.fontSize, 20)
        XCTAssertEqual(style.fontFamilyWeight, 400)
        XCTAssertEqual(style.jsonObject["titleSize"] as? Double, 34)
        XCTAssertEqual(style.jsonObject["titleWeight"] as? Int, 400)
        XCTAssertEqual(style.jsonObject["titleFontFamily"] as? String, ReaderFontFamily.maShanZheng.webCSSFamily)
        XCTAssertTrue(style.customFontFaceCSS.contains("@font-face"), "A title-only font must reach the WebContent process")
    }

    func testFontSelectionValidatesContentsInsteadOfProviderTypeLabels() throws {
        for suffix in ["ttf", "OTF", "ttc", "otc"] { XCTAssertNoThrow(try FontImportPolicy.validate(suffix: suffix, bytes: 1024)) }
        XCTAssertThrowsError(try FontImportPolicy.validate(suffix: "zip", bytes: 1024))
        XCTAssertThrowsError(try FontImportPolicy.validate(suffix: "ttf", bytes: 0))
        XCTAssertThrowsError(try FontImportPolicy.validate(suffix: "ttf", bytes: FontImportPolicy.maximumBytes + 1))
    }

    @MainActor func testInvalidFontCannotReplaceAnExistingValidFont() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fonts = CustomFontManager(rootURL: root.appendingPathComponent("installed"))
        let bundled = try XCTUnwrap(Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil)?.first)
        let first = try fonts.importFont(from: bundled)
        let saved = fonts.fontsDirectory.appendingPathComponent(first.fileName)
        let original = try Data(contentsOf: saved)
        let invalid = root.appendingPathComponent(bundled.lastPathComponent)
        try Data("not a font".utf8).write(to: invalid)
        XCTAssertThrowsError(try fonts.importFont(from: invalid))
        XCTAssertEqual(try Data(contentsOf: saved), original)
        XCTAssertEqual(fonts.installedFonts.count, 1)
        XCTAssertEqual(try fonts.importFont(from: bundled).postScriptName, first.postScriptName)
        XCTAssertEqual(fonts.installedFonts.count, 1)
    }

    @MainActor func testMountedNewThemeStructuresAndContinuousWallpaperHeader() async throws {
        let defaults = UserDefaults.standard, key = "settings.visualTheme", old = defaults.object(forKey: key)
        defer { if let old { defaults.set(old, forKey: key) } else { defaults.removeObject(forKey: key) } }
        for theme in [AppVisualTheme.folio, .inkwash, .blueprint] {
            defaults.set(theme.rawValue, forKey: key)
            try await capture(VStack(spacing: 20) {
                Text(theme.title).font(.system(.title, design: theme.fontDesign))
                VStack(alignment: .leading, spacing: 12) {
                    Label("我的书架", systemImage: theme.ornament).font(.headline)
                    Text("不是只换颜色：票根切口、留白与网格，各有自己的纸面结构。")
                }.padding(24).glassPanel()
                AppearanceSettingsView()
            }.padding().pageBackground(), name: "theme-" + theme.rawValue, width: 390)
        }
        let geometry = ReaderScrollChromeGeometry(safeTop: 59, headerVisible: true, showSystemStatusBar: true)
        try await capture(VStack(spacing: 0) {
            ReaderScrollChapterHeader(title: "第一章 · 山中来信", geometry: geometry, horizontalPadding: 21,
                                      foreground: .white, paper: .white, wallpaper: AnyView(Color.indigo)) { EmptyView() }
            Text("壁纸应延伸至状态栏与页眉，正文不会从固定页眉下透出。")
                .font(.title2).padding(24).frame(maxHeight: .infinity)
        }.background(Color.indigo).foregroundStyle(.white), name: "wallpaper-header", width: 390)
    }

    @MainActor private func capture<Content: View>(_ content: Content, name: String, width: CGFloat) async throws {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previous = scene?.windows.first(where: \.isKeyWindow)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = UIScreen.main.bounds
        let parent = UIViewController(), host = UIHostingController(rootView: content)
        window.rootViewController = parent; window.makeKeyAndVisible()
        parent.addChild(host); parent.view.addSubview(host.view)
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: 844); host.didMove(toParent: parent)
        defer { window.isHidden = true; previous?.makeKey() }
        try await Task.sleep(nanoseconds: 400_000_000); host.view.layoutIfNeeded()
        XCTAssertEqual(host.view.bounds.width, width, accuracy: 1)
        let picture = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: picture); attachment.name = "release117-motion-" + name
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
