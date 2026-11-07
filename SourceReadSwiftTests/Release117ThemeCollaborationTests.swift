import SwiftUI
import XCTest
@testable import SourceReadSwift

final class Release117ThemeCollaborationTests: XCTestCase {
    func testSurfacePolicyUsesRuntimeCapabilitiesAndAccessibilityRatherThanThemeSelection() {
        for theme in AppVisualTheme.allCases {
            XCTAssertEqual(AppThemeSurfaceStyle.resolve(theme: theme, nativeGlassAvailable: false, reduceTransparency: false, increasedContrast: false), [AppVisualTheme.classic, .forest].contains(theme) ? .legacyMaterial : .paper)
            XCTAssertEqual(AppThemeSurfaceStyle.resolve(theme: theme, nativeGlassAvailable: true, reduceTransparency: false, increasedContrast: false), [AppVisualTheme.classic, .forest].contains(theme) ? .nativeGlass : .paper)
            XCTAssertEqual(AppThemeSurfaceStyle.resolve(theme: theme, nativeGlassAvailable: true, reduceTransparency: true, increasedContrast: false), .paper)
            XCTAssertEqual(AppThemeSurfaceStyle.resolve(theme: theme, nativeGlassAvailable: true, reduceTransparency: false, increasedContrast: true), .paper)
        }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { XCTAssertTrue(AppThemeSurfaceStyle.nativeGlassAvailable) }
        else { XCTAssertFalse(AppThemeSurfaceStyle.nativeGlassAvailable) }
        #else
        XCTAssertFalse(AppThemeSurfaceStyle.nativeGlassAvailable)
        #endif
    }

    func testAllDefaultThemesIncludeReadableClassicDarkAccent() {
        for theme in AppVisualTheme.allCases {
            for (foreground, background) in [(theme.accentHex, theme.cardHex), (theme.darkAccentHex, theme.darkCardHex)] {
                let a = luminance(foreground), b = luminance(background)
                XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5, theme.title)
            }
        }
    }

    @MainActor func testMountedRowRepaintsAndEditorDraftSurvivesThemeChange() async throws {
        let defaults = UserDefaults.standard, key = "settings.visualTheme"
        let old = defaults.object(forKey: key)
        defer { if let old { defaults.set(old, forKey: key) } else { defaults.removeObject(forKey: key) } }
        defaults.set("editorial", forKey: key)
        let row = UIHostingController(rootView: AppThemeRowSurface())
        row.view.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        let window = mount(row)
        defer { window.isHidden = true }
        let mounted = await eventually { row.view.window === window && !row.view.bounds.isEmpty }
        XCTAssertTrue(mounted)
        let before = snapshot(row.view).pngData()
        defaults.set("coast", forKey: key)
        let repainted = await eventually { before != self.snapshot(row.view).pngData() }
        XCTAssertTrue(repainted, "An existing mounted row must apply the new palette")
        XCTAssertNotEqual(before, snapshot(row.view).pngData(), "An existing row must repaint without recreating its screen")
        let editor = UIHostingController(rootView: ThemeDraftFixture())
        window.rootViewController = editor
        editor.view.frame = window.bounds
        let editorMounted = await eventually { self.findField(editor.view) != nil }
        XCTAssertTrue(editorMounted, "Form must mount its real input before editing the draft")
        let field = try XCTUnwrap(findField(editor.view))
        field.text = "unsaved-theme-draft"; field.sendActions(for: .editingChanged)
        defaults.set("graphite", forKey: key)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(findField(editor.view) === field, "Theme changes must not replace the editor")
        XCTAssertEqual(field.text, "unsaved-theme-draft")
    }

    @MainActor func testSourceLoginPurificationAndRuleEditorMountedEvidence() async throws {
        let defaults = UserDefaults.standard, key = "settings.visualTheme"
        let old = defaults.object(forKey: key)
        defer { if let old { defaults.set(old, forKey: key) } else { defaults.removeObject(forKey: key) } }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = AppState(sourceStore: SourceStore(persistence: SourcePersistence(rootURL: folder)))
        let source = BookSource(bookSourceName: "主题回归样本", bookSourceUrl: "https://theme.example", searchUrl: "/search?q={{key}}")
        let pages: [(String, AnyView)] = [
            ("source-login", AnyView(SourceLoginCenterView(sources: [source], cookieStore: app.sourceCookieStore))),
            ("purification", AnyView(PurifyRulesView())),
            ("rule-editor", AnyView(SourceRuleEditorView(source: source, onSave: { _ in XCTFail("Rendering cannot save rules") }, onCancel: {})))
        ]
        for (theme, style, width) in [("editorial", UIUserInterfaceStyle.light, CGFloat(320)), ("classic", .dark, CGFloat(390))] {
            defaults.set(theme, forKey: key)
            for (name, page) in pages {
                let host = UIHostingController(rootView: NavigationStack { page.environmentObject(app) })
                host.overrideUserInterfaceStyle = style
                let window = mount(host)
                host.view.frame = CGRect(x: 0, y: 0, width: width, height: 844)
                try await Task.sleep(nanoseconds: 250_000_000)
                host.view.layoutIfNeeded()
                XCTAssertEqual(host.view.bounds.width, width, accuracy: 1)
                let attachment = XCTAttachment(image: snapshot(host.view))
                attachment.name = "release117-theme-\(theme)-\(name)-\(Int(width))"
                attachment.lifetime = .keepAlways; add(attachment)
                window.isHidden = true
            }
        }
    }

    private func luminance(_ rgb: UInt32) -> Double {
        let channels = [16, 8, 0].map { shift -> Double in
            let channel = Double((rgb >> shift) & 255) / 255
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
    }
    @MainActor private func mount(_ controller: UIViewController) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = UIScreen.main.bounds; window.rootViewController = controller; window.makeKeyAndVisible()
        return window
    }
    @MainActor private func snapshot(_ view: UIView) -> UIImage {
        view.layoutIfNeeded()
        return UIGraphicsImageRenderer(size: view.bounds.size).image { _ in view.drawHierarchy(in: view.bounds, afterScreenUpdates: true) }
    }
    @MainActor private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<60 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }
    @MainActor private func findField(_ view: UIView) -> UITextField? {
        if let field = view as? UITextField { return field }
        return view.subviews.lazy.compactMap { self.findField($0) }.first
    }
}

private struct ThemeDraftFixture: View {
    @State private var draft = "draft"
    var body: some View {
        Form { TextField("规则草稿", text: $draft).listRowBackground(AppThemeRowSurface()) }.pageBackground()
    }
}
