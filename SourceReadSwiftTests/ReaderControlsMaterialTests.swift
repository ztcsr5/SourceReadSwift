import SwiftUI
import XCTest
@testable import SourceReadSwift

final class ReaderControlsMaterialTests: XCTestCase {
    func testSystemMaterialRequiresTheActualUserPermissionAndSelection() {
        XCTAssertTrue(ReaderChromeSurface.permitsTranslucency(reduceTransparency: false,
            increasedContrast: false, menuStyle: "system", usesWallpaper: false))
        for (reduce, contrast, style, wallpaper) in [(true, false, "system", false),
            (false, true, "system", false), (false, false, "paper", false),
            (false, false, "system", true), (false, false, "invalid", false)] {
            XCTAssertFalse(ReaderChromeSurface.permitsTranslucency(reduceTransparency: reduce,
                increasedContrast: contrast, menuStyle: style, usesWallpaper: wallpaper))
            XCTAssertFalse(ReaderChromeSurface.usesNativeGlass(reduceTransparency: reduce,
                increasedContrast: contrast, menuStyle: style, usesWallpaper: wallpaper))
        }
    }

    @MainActor func testSystemAndPaperChoicesActuallyChangeTheSettingsSurface() async throws {
        let defaults = UserDefaults.standard
        let keys = ["reader.menuSurfaceStyle", "reader.menuUsesWallpaper"]
        let previous = keys.map { defaults.object(forKey: $0) }
        let keyWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
            keyWindow?.makeKey()
        }
        defaults.set(false, forKey: keys[1])
        var pictures: [UIImage] = []
        for style in ["system", "paper"] {
            defaults.set(style, forKey: keys[0])
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            let host = UIHostingController(rootView: ZStack {
                LinearGradient(colors: [.blue, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                ReaderSettingsWorkbench(context: ReaderWorkbenchContext(bookTitle: "材质集成测试", background: .white,
                    bottomInset: 0, initialRoute: .typography), preview: { AnyView(Text("书页")) },
                    page: { _ in AnyView(Text("字体与纸面")) }, actions: ReaderWorkbenchActions(close: {}))
            }.environment(\.accessibilityReduceTransparency, false).environment(\.colorSchemeContrast, .standard)
                .environment(\.colorScheme, .light))
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(nanoseconds: 300_000_000)
            host.view.layoutIfNeeded()
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 844))
            let picture = renderer.image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            pictures.append(picture)
            let attachment = XCTAttachment(image: picture)
            attachment.name = "reader-controls-material-" + style
            attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true
        }
        XCTAssertNotEqual(pictures[0].pngData(), pictures[1].pngData(),
            "The actual settings panel must honor the system/paper choice, not ignore it")
    }
}
