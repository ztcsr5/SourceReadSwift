import SwiftUI
import XCTest
@testable import SourceReadSwift

final class FloatingReadingDeskTests: XCTestCase {
    func testReturnSlotsKeepLatestMetadataAndInvalidateWhenMembershipChanges() {
        let first = makeBook()
        var second = BookshelfBook(id: "other", title: "第二本", author: "", coverURL: nil,
            sourceName: "本地", sourceURL: "local://text", bookURL: "local://other", intro: nil)
        second.currentChapterIndex = 5
        let restored = BookReturnOrder.restore([second, first], ids: [first.id, second.id])
        XCTAssertEqual(restored?.map(\.id), [first.id, second.id])
        XCTAssertEqual(restored?.last?.currentChapterIndex, 5)
        XCTAssertNil(BookReturnOrder.restore([second], ids: [first.id, second.id]))
        XCTAssertNil(BookReturnOrder.restore([second], ids: [first.id]))
    }
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
        XCTAssertLessThanOrEqual(regular.height, 290, "The revised composition must reclaim height, not shrink the bookshelf")
        XCTAssertLessThan(old.height, regular.height, "The independent switch must really preserve the previous compact card")
        XCTAssertGreaterThan(accessible.height, regular.height, "Accessibility text must grow, not get clipped by a fixed card")
    }

    @MainActor func testDeskFirstFrameUsesExactRasterInsteadOfShelfHandoff() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = makeCoverRaster(size: CGSize(width: 400, height: 600), color: .green)
        let shelf = makeCoverRaster(size: CGSize(width: 40, height: 60), color: .magenta)
        try XCTUnwrap(original.pngData()).write(to: url)
        let budget = ReadingDeskCoverRaster.maximumPixelSize(points: 150, scale: 1)
        let image = await RemoteImageLoader.shared.image(for: url, maxPixelSize: budget, reuseCoverBytes: true)
        XCTAssertEqual(image?.cgImage?.height, 180)
        let handoff = ReadingCoverHandoff()
        handoff.retain(shelf, for: url)
        let renderer = ImageRenderer(content: AsyncBookCover(urlString: url.absoluteString, width: 100, height: 150, prefersDeskRaster: true)
            .environment(\.readingCoverHandoff, handoff).environment(\.displayScale, 1))
        renderer.scale = 1
        XCTAssertGreaterThan(try measureAverageGreen(XCTUnwrap(renderer.uiImage)), 0.8)
    }

    @MainActor func testDeskCoverSizesShareOriginalAndKeepLowResolutionNative() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.protocolClasses = [DeskCoverURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let loader = RemoteImageLoader(session: session)
        let original = try XCTUnwrap(makeCoverRaster(size: CGSize(width: 800, height: 1200), color: .purple).pngData())
        let low = try XCTUnwrap(makeCoverRaster(size: CGSize(width: 48, height: 72), color: .green).pngData())
        let shelfPixels: CGFloat = 176
        let deskPixels = ReadingDeskCoverRaster.maximumPixelSize(points: 194, scale: 3)
        XCTAssertEqual(deskPixels, 699)
        for (bytes, cacheControl, expectsSharedBytes) in [(original, "max-age=120", true), (low, "no-store", false)] {
            let url = URL(string: "https://desk-cover-fixture.invalid/\(UUID().uuidString).png")!
            DeskCoverURLProtocol.register(bytes, cacheControl: cacheControl, for: url)
            defer { DeskCoverURLProtocol.remove(url) }
            let shelf = await loader.image(for: url, maxPixelSize: shelfPixels, reuseCoverBytes: true)
            let desk = await loader.image(for: url, maxPixelSize: deskPixels, reuseCoverBytes: true)
            XCTAssertEqual(shelf?.cgImage?.height, expectsSharedBytes ? 176 : 72)
            XCTAssertEqual(desk?.cgImage?.height, expectsSharedBytes ? 699 : 72)
            XCTAssertEqual(DeskCoverURLProtocol.count(for: url), expectsSharedBytes ? 1 : 2)
            XCTAssertNil(loader.cachedImage(for: url, maxPixelSize: deskPixels), "The cover raster cannot leak into the illustration namespace")
            XCTAssertTrue(loader.cachedImage(for: url, maxPixelSize: deskPixels, reuseCoverBytes: true) === desk)
        }
    }

    func testCoverByteCacheDoesNotExtendServerFreshness() {
        XCTAssertEqual(CoverSourceBytes.freshness(cacheControl: "max-age=90", age: "80", hasExplicitExpiry: false), 10)
        XCTAssertEqual(CoverSourceBytes.freshness(cacheControl: "max-age=2", age: "12", hasExplicitExpiry: false), 0)
        XCTAssertEqual(CoverSourceBytes.freshness(cacheControl: "public, max-age=3600", age: nil, hasExplicitExpiry: false), 300)
        XCTAssertEqual(CoverSourceBytes.freshness(cacheControl: "private, max-age=3600", age: nil, hasExplicitExpiry: false), 0)
        XCTAssertEqual(CoverSourceBytes.freshness(cacheControl: "", age: nil, hasExplicitExpiry: true), 0)
    }

    @MainActor private func makeCoverRaster(size: CGSize, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testOpeningIntroductionSharesTheBoundedPlainTextOfTheDesk() {
        XCTAssertEqual(ReadingDeskContent.introduction(from: "<p>山中有信。&nbsp;\n书页未尽。</p>"), "山中有信。 书页未尽。")
        XCTAssertNil(ReadingDeskContent.introduction(from: "<p> &nbsp; </p>"))
        XCTAssertNil(ReadingDeskContent.introduction(from: nil))
        XCTAssertEqual(ReadingDeskContent.introduction(from: String(repeating: "正文", count: 5000))?.count, 120)
    }

    func testContextUsesPersistedChapterOrRealIntroductionWithoutInventingAtmosphere() {
        var book = makeBook()
        book.latestChapterTitle = "最新一章不能冒充阅读位置"
        XCTAssertEqual(ReadingDeskContent.chapterNumber(for: book), "64")
        XCTAssertEqual(ReadingDeskContent.contextLine(for: book), "上次读到 · 第六十四章 · 写给下一页的信")
        book.currentChapterIndex = Int.max
        XCTAssertEqual(ReadingDeskContent.chapterNumber(for: book), "100")
        book.currentChapterIndex = Int.min
        XCTAssertEqual(ReadingDeskContent.chapterNumber(for: book), "1")
        book.currentChapterTitle = nil; book.intro = "<p>山中有信。&nbsp;\n 书页未尽。</p>"
        XCTAssertEqual(ReadingDeskContent.contextLine(for: book), "山中有信。 书页未尽。")
        book.lastReadAt = nil; book.intro = nil
        XCTAssertNil(ReadingDeskContent.chapterNumber(for: book))
        XCTAssertEqual(ReadingDeskContent.contextLine(for: book), "从第一页开始")
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
        for width: CGFloat in [288, 342, 398] {
            let longHeight = UIHostingController(rootView: ReadingHeroCard(book: long, usesFloatingStyle: true))
                .sizeThatFits(in: CGSize(width: width, height: 6000)).height
            for name in ["剑来", "凡人修仙传", "第 12 卷：夜航 Lab 2.0 / 封印·回声与时间的裂缝"] {
                var book = long; book.title = name; book.author = "纸间"
                let height = UIHostingController(rootView: ReadingHeroCard(book: book, usesFloatingStyle: true))
                    .sizeThatFits(in: CGSize(width: width, height: 6000)).height
                XCTAssertEqual(longHeight, height, accuracy: 1, "Horizontal paging must not resize the shelf underneath a drag")
            }
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

private final class DeskCoverURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Fixture {
        let bytes: Data
        let cacheControl: String
        var requests = 0
    }
    private static let lock = NSLock()
    private static var fixtures: [URL: Fixture] = [:]

    static func register(_ bytes: Data, cacheControl: String, for url: URL) {
        lock.lock(); defer { lock.unlock() }
        fixtures[url] = Fixture(bytes: bytes, cacheControl: cacheControl)
    }

    static func remove(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        fixtures[url] = nil
    }

    static func count(for url: URL) -> Int {
        lock.lock(); defer { lock.unlock() }
        return fixtures[url]?.requests ?? 0
    }

    private static func consume(_ url: URL) -> Fixture? {
        lock.lock(); defer { lock.unlock() }
        fixtures[url]?.requests += 1
        return fixtures[url]
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "desk-cover-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let fixture = Self.consume(url),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                  headerFields: ["Content-Type": "image/png", "Cache-Control": fixture.cacheControl]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: fixture.bytes)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
