import SwiftUI
import XCTest
import UIKit
@testable import SourceReadSwift

final class ReaderControlsMaterialTests: XCTestCase {
    @MainActor func testComicControlsRemainLegibleOverAWhiteImage() throws {
        let surface = ZStack {
            Color.white
            ComicChromeSurface(shape: Rectangle())
        }.frame(width: 390, height: 844)
        let bitmap = try XCTUnwrap(ImageRenderer(content: surface).uiImage)
        let background = try surfaceChannels(bitmap).map { $0 / 255 }
        func luminance(_ channels: [Double]) -> Double {
            zip(channels, [0.2126, 0.7152, 0.0722]).reduce(0) { total, channel in
                let value = channel.0
                let linear = value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
                return total + channel.1 * linear
            }
        }
        let secondaryInk = background.map { $0 + (1 - $0) * ComicChromePalette.secondaryInkOpacity }
        let contrast = (luminance(secondaryInk) + 0.05) / (luminance(background) + 0.05)
        XCTAssertGreaterThanOrEqual(contrast, 4.5, "The chapter label must remain readable above a bright image")
    }

    @MainActor func testUnchangedReadingProgressDoesNotReplaceTheOpenNativeMenu() {
        let button = UIButton(type: .system)
        let coordinator = ReaderNativeMenuButton.Coordinator()
        var builds = 0
        func makeMenu() -> UIMenu {
            builds += 1
            return UIMenu(children: [UIAction(title: "当前章节 \(builds)") { _ in }])
        }
        coordinator.apply(to: button, identity: "chapter-1|idle", makeMenu: makeMenu)
        let original = button.menu
        for _ in 0..<50 {
            coordinator.apply(to: button, identity: "chapter-1|idle", makeMenu: makeMenu)
        }
        XCTAssertEqual(builds, 1)
        XCTAssertTrue(button.menu === original, "Progress-only refreshes must not replace UIKit's presented menu")
        coordinator.apply(to: button, identity: "chapter-2|idle", makeMenu: makeMenu)
        XCTAssertEqual(builds, 2)
        XCTAssertFalse(button.menu === original, "Changing the real chapter must refresh the actions")
    }

    @MainActor func testOldMenuDismissalCannotUnblockTapsDuringANewerPresentation() {
        let guardState = ReaderMenuPresentation()
        let first = UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: nil)
        let second = UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: nil)
        XCTAssertFalse(guardState.isActive)
        guardState.begin(ObjectIdentifier(first))
        XCTAssertTrue(guardState.isActive)
        guardState.begin(ObjectIdentifier(second))
        guardState.end(ObjectIdentifier(first))
        XCTAssertTrue(guardState.isActive)
        guardState.end(ObjectIdentifier(second))
        XCTAssertFalse(guardState.isActive)
    }

    @MainActor func testSurfaceSamplerReadsTheLowerPanelNotTheUpperBackdrop() throws {
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 844)).image { renderer in
            UIColor.black.setFill(); renderer.fill(CGRect(x: 0, y: 0, width: 390, height: 844))
            UIColor.red.setFill(); renderer.fill(CGRect(x: 0, y: 422, width: 390, height: 422))
        }
        let channels = try surfaceChannels(picture)
        XCTAssertEqual(channels[0], 255, accuracy: 1)
        XCTAssertEqual(channels[1], 0, accuracy: 1)
        XCTAssertEqual(channels[2], 0, accuracy: 1)
    }

    func testSystemMaterialRequiresTheActualUserPermissionAndSelection() {
        XCTAssertTrue(ReaderChromeSurface.permitsTranslucency(reduceTransparency: false,
            increasedContrast: false, menuStyle: "system", usesWallpaper: false))
        XCTAssertTrue(ReaderChromeSurface.permitsTranslucency(reduceTransparency: false,
            increasedContrast: false, menuStyle: "system", usesWallpaper: true))
        for (reduce, contrast, style, wallpaper) in [(true, false, "system", false),
            (false, true, "system", false), (false, false, "paper", false),
            (false, false, "invalid", false)] {
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
            // CGImage scanlines already match the bitmap's row order. A UIKit
            // drawing flip here would sample the upper backdrop instead.
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
