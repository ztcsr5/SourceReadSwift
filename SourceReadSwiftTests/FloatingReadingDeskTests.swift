import SwiftUI
import XCTest
@testable import SourceReadSwift

final class FloatingReadingDeskTests: XCTestCase {
    func testAccessibilityAndEnergyPoliciesCoverEveryCombination() {
        for bits in 0..<32 {
            let motion = bits & 1 != 0, transparency = bits & 2 != 0, contrast = bits & 4 != 0
            let energy = bits & 8 != 0, native = bits & 16 != 0
            let policy = FloatingDeskPolicy.resolve(.init(reducesMotion: motion, reducesTransparency: transparency,
                increasedContrast: contrast, conservesEnergy: energy), hasLiquidGlass: native)
            XCTAssertEqual(policy.reducesDepth, motion || energy)
            XCTAssertEqual(policy.surface, transparency || contrast || energy ? .opaque : native ? .liquidGlass : .material)
        }
    }

    func testThemeAdaptationIncludesMaterialAndDepthNotOnlyColor() {
        let luminous = FloatingDeskPalette.resolve(theme: .classic).finish
        let quiet = FloatingDeskPalette.resolve(theme: .editorial).finish
        XCTAssertGreaterThan(luminous.environmentStrength, quiet.environmentStrength)
        XCTAssertLessThan(luminous.glassTintOpacity, quiet.glassTintOpacity)
        XCTAssertGreaterThan(luminous.parallaxStrength, quiet.parallaxStrength)
    }

    @MainActor func testCoverHandoffRendersTheSameDecodedImageOnTheFirstFrameAndIsURLScoped() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let other = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let cover = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 150)).image { context in
            UIColor.magenta.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 150))
        }
        let handoff = ReadingCoverHandoff(); handoff.retain(cover, for: url)
        XCTAssertTrue(handoff.image(for: url) === cover, "Handoff must retain the already-decoded bitmap, not copy or decode it again")
        XCTAssertNil(handoff.image(for: other), "A different book URL must never borrow this cover")
        let scenarios: [(URL, ReadingCoverHandoff?, Bool)] = [(url, handoff, false), (url, nil, true), (other, handoff, true)]
        for (address, context, expectedGreen) in scenarios {
            let renderer = ImageRenderer(content: AsyncBookCover(urlString: address.absoluteString, width: 100, height: 150)
                .environment(\.readingCoverHandoff, context).environment(\.colorScheme, .light))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            let green = try measureAverageGreen(image)
            if expectedGreen { XCTAssertGreaterThan(green, 0.5, "No opt-in/context match must preserve the normal paper placeholder") }
            else { XCTAssertLessThan(green, 0.2, "The very first render must already show the source cover, before any async task") }
        }
        handoff.clear()
        XCTAssertNil(handoff.image(for: url), "Disabling the experiment must release the handoff references")
    }

    @MainActor func testLargeCoverAndCompactEnvelopeWithoutChangingTheOldCard() {
        let regular = measure(usesFloatingStyle: true, type: .large)
        let old = measure(usesFloatingStyle: false, type: .large)
        let accessible = measure(usesFloatingStyle: true, type: .accessibility3)
        XCTAssertEqual(regular.width, 342, accuracy: 1)
        XCTAssertGreaterThanOrEqual(regular.height, 280)
        XCTAssertLessThanOrEqual(regular.height, 330)
        XCTAssertLessThan(old.height, regular.height, "The independent switch must really preserve the previous compact card")
        XCTAssertGreaterThan(accessible.height, regular.height, "Accessibility text must grow, not get clipped by a fixed card")
    }

    @MainActor func testMountedThemesLongTitlesAndAccessibilityEvidence() async throws {
        let defaults = UserDefaults.standard
        let key = "settings.visualTheme", oldTheme = defaults.object(forKey: key)
        let motionKey = "settings.reducesMotion", oldMotion = defaults.object(forKey: motionKey)
        defer {
            if let oldTheme { defaults.set(oldTheme, forKey: key) } else { defaults.removeObject(forKey: key) }
            if let oldMotion { defaults.set(oldMotion, forKey: motionKey) } else { defaults.removeObject(forKey: motionKey) }
        }
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        defer { previous?.makeKey() }
        for (theme, dark, width, accessible) in [
            (AppVisualTheme.classic, false, CGFloat(390), false), (.classic, true, 390, false),
            (.botanical, false, 390, false), (.editorial, false, 390, false),
            (.classic, false, 320, false), (.classic, false, 320, true)
        ] {
            defaults.set(theme.rawValue, forKey: key)
            defaults.set(accessible, forKey: motionKey)
            let content = ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("正在阅读").font(.title2.weight(.semibold))
                    ReadingHeroCard(book: makeBook(), usesFloatingStyle: true)
                    Text("我的书架").font(.title2.weight(.semibold))
                    Text("书架必须在首屏继续可见，不因主视觉挤到屏幕之外。")
                }.padding(24)
            }.frame(maxHeight: .infinity, alignment: .top).background(AppTheme.background)
                .environment(\.dynamicTypeSize, accessible ? .accessibility3 : .large)
                .preferredColorScheme(dark ? .dark : .light)
            let host = UIHostingController(rootView: content)
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
            window.frame = UIScreen.main.bounds
            window.overrideUserInterfaceStyle = dark ? .dark : .light
            let parent = UIViewController(); window.rootViewController = parent; window.makeKeyAndVisible()
            parent.addChild(host)
            parent.setOverrideTraitCollection(UITraitCollection(accessibilityContrast: accessible ? .high : .normal), forChild: host)
            parent.view.addSubview(host.view)
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: 844); host.didMove(toParent: parent)
            try await Task.sleep(nanoseconds: 350_000_000)
            host.view.layoutIfNeeded()
            XCTAssertEqual(host.view.bounds.width, width, accuracy: 1)
            XCTAssertEqual(host.traitCollection.accessibilityContrast, accessible ? .high : .normal)
            XCTAssertEqual(host.traitCollection.userInterfaceStyle, dark ? .dark : .light)
            let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "floating-desk-\(theme.rawValue)-\(dark ? "dark" : "light")-\(Int(width))-\(accessible ? "accessible" : "normal")"
            attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true
        }
    }

    @MainActor func testPagingDoesNotChangeHeightWhenTheNextTitleIsLong() {
        let long = makeBook()
        var short = long; short.title = "山海来信"; short.author = "纸间"
        for width: CGFloat in [288, 342, 398] {
            let longHeight = UIHostingController(rootView: ReadingHeroCard(book: long, usesFloatingStyle: true))
                .sizeThatFits(in: CGSize(width: width, height: 6000)).height
            let shortHeight = UIHostingController(rootView: ReadingHeroCard(book: short, usesFloatingStyle: true))
                .sizeThatFits(in: CGSize(width: width, height: 6000)).height
            XCTAssertEqual(longHeight, shortHeight, accuracy: 1, "Horizontal paging must not resize the shelf underneath a drag")
        }
    }

    private func makeBook() -> BookshelfBook {
        var book = BookshelfBook(id: "desk-long-title", title: "白昼之后，我们把很长很长的信写给远方与尚未相逢的人",
            author: "一位名字也非常长的作者", coverURL: nil, sourceName: "离线验收", sourceURL: "local://text", bookURL: "local://desk", intro: nil)
        book.lastReadAt = Date(timeIntervalSince1970: 1)
        book.totalChapters = 100; book.currentChapterIndex = 63; book.currentChapterTitle = "第六十四章 · 写给下一页的信"
        return book
    }

    @MainActor private func measure(usesFloatingStyle: Bool, type: DynamicTypeSize) -> CGSize {
        UIHostingController(rootView: ReadingHeroCard(book: makeBook(), usesFloatingStyle: usesFloatingStyle)
            .environment(\.dynamicTypeSize, type)).sizeThatFits(in: CGSize(width: 342, height: 6000))
    }

    private func measureAverageGreen(_ image: UIImage) throws -> Double {
        let source = try XCTUnwrap(image.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let green: Double = try pixel.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return Double(bytes[1]) / 255
        }
        return green
    }
}
