import SwiftUI
import XCTest
import UIKit
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
        XCTAssertFalse(UIAccessibility.isReduceTransparencyEnabled,
            "The material fixture requires the runner's default transparency permission")
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
            window.overrideUserInterfaceStyle = .light
            let host = UIHostingController(rootView: ZStack {
                LinearGradient(colors: [.blue, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                ReaderSettingsWorkbench(context: ReaderWorkbenchContext(bookTitle: "材质集成测试", background: .white,
                    bottomInset: 0, initialRoute: .typography), preview: { AnyView(Text("书页")) },
                    page: { _ in AnyView(Text("字体与纸面")) }, actions: ReaderWorkbenchActions(close: {}))
            }.environment(\.colorScheme, .light))
            host.overrideUserInterfaceStyle = .light
            let parent = UIViewController(); window.rootViewController = parent
            parent.addChild(host)
            parent.setOverrideTraitCollection(UITraitCollection(accessibilityContrast: .normal), forChild: host)
            parent.view.addSubview(host.view); host.view.frame = window.bounds; host.didMove(toParent: parent)
            window.makeKeyAndVisible()
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
        let glass = try surfaceChannels(pictures[0]), paper = try surfaceChannels(pictures[1])
        let difference = zip(glass, paper).map { abs($0 - $1) }.reduce(0, +) / 3
        XCTAssertGreaterThan(difference, 8,
            "Settings must visibly honor system/paper selection; mean channel difference was \(difference)")
    }

    private func surfaceChannels(_ image: UIImage) throws -> [Double] {
        let picture = try XCTUnwrap(image.cgImage)
        let width = 390, height = 844
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
            context.draw(picture, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        XCTAssertTrue(rendered)
        // The empty lower-middle panel excludes labels, buttons and the screen's
        // status area. Compare actual pixels, not PNG encoding or changing text.
        var channels = [0.0, 0.0, 0.0], count = 0.0
        for y in stride(from: 540, to: 680, by: 8) {
            for x in stride(from: 80, to: 310, by: 8) {
                let offset = (y * width + x) * 4
                for channel in 0..<3 { channels[channel] += Double(pixels[offset + channel]) }
                count += 1
            }
        }
        return channels.map { $0 / count }
    }
}
