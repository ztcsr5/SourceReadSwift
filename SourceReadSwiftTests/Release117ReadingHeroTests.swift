import SwiftUI
import XCTest
@testable import SourceReadSwift

final class Release117ReadingHeroTests: XCTestCase {
    func testOnlyPersistedProgressAndLastReadChapterAreReported() {
        var book = makeBook()
        book.latestChapterTitle = "最新章节不能冒充上次阅读"
        XCTAssertEqual(ReadingHeroStatus.progress(for: book), "待开始")
        XCTAssertEqual(ReadingHeroStatus.chapter(for: book), "从第一页开始")
        book.lastReadAt = Date(timeIntervalSince1970: 1)
        XCTAssertEqual(ReadingHeroStatus.progress(for: book), "进度待记录")
        XCTAssertEqual(ReadingHeroStatus.chapter(for: book), "上次位置待记录")
        book.totalChapters = 20; book.currentChapterIndex = 6
        book.currentChapterTitle = "  第七章 · 灯塔  "
        XCTAssertEqual(ReadingHeroStatus.progress(for: book), "章节进度 35%")
        XCTAssertEqual(ReadingHeroStatus.chapter(for: book), "上次读到 · 第七章 · 灯塔")
        book.currentChapterIndex = Int.max
        XCTAssertEqual(ReadingHeroStatus.progress(for: book), "章节进度 100%")
        book.currentChapterIndex = Int.min
        XCTAssertEqual(ReadingHeroStatus.progress(for: book), "章节进度 5%")
    }

    @MainActor func testCoverSamplingLeavesMainActorAndCachesMutedResultsAndFallbacks() async throws {
        let sampler = CoverToneSampler()
        let red = makeCover(.red), blue = makeCover(.blue), white = makeCover(.white)
        XCTAssertFalse(sampler.hasCachedTone(for: red))
        let sampledRed = await sampler.tone(for: red), sampledBlue = await sampler.tone(for: blue)
        let redTone = try XCTUnwrap(sampledRed)
        let blueTone = try XCTUnwrap(sampledBlue)
        XCTAssertGreaterThan(redTone.red, redTone.blue)
        XCTAssertGreaterThan(blueTone.blue, blueTone.red)
        XCTAssertLessThanOrEqual(max(redTone.red, redTone.green, redTone.blue) - min(redTone.red, redTone.green, redTone.blue), 0.17)
        XCTAssertTrue(sampler.hasCachedTone(for: red))
        let again = await sampler.tone(for: red)
        XCTAssertEqual(again, redTone)
        let fallback = await sampler.tone(for: white)
        XCTAssertNil(fallback, "An all-white or missing cover uses the theme rather than invented colour")
        XCTAssertTrue(sampler.hasCachedTone(for: white), "Fallbacks must be cached too")
    }

    @MainActor func testHorizontalHeroGrowsForAccessibilityWithoutShrinkingTextOrCover() {
        let regular = measure(type: .large), accessible = measure(type: .accessibility3)
        XCTAssertEqual(regular.width, 288, accuracy: 1)
        XCTAssertGreaterThanOrEqual(regular.height, 160)
        XCTAssertEqual(accessible.width, 288, accuracy: 1)
        XCTAssertGreaterThan(accessible.height, regular.height)
    }

    @MainActor func testMountedHeroNarrowNormalDarkAndLargeTypeEvidence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cover = root.appendingPathComponent("cover.png")
        try XCTUnwrap(makeCover(.systemTeal).pngData()).write(to: cover)
        let previousKeyWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        defer { previousKeyWindow?.makeKey() }
        for (width, isDark, isLarge) in [(CGFloat(320), false, false), (390, true, false), (320, false, true)] {
            var book = makeBook(); book.coverURL = cover.absoluteString
            book.lastReadAt = Date(timeIntervalSince1970: 1); book.totalChapters = 20
            book.currentChapterIndex = 6; book.currentChapterTitle = "第七章 · 远处的灯塔"
            let host = UIHostingController(rootView: ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("正在阅读").font(.title2.weight(.semibold))
                    Text("把这一刻，留给下一页。").font(.subheadline).foregroundStyle(.secondary)
                    ReadingHeroCard(book: book)
                }.padding(16)
            }.background(AppTheme.background)
                .environment(\.dynamicTypeSize, isLarge ? .accessibility3 : .large)
                .environment(\.colorSchemeContrast, isLarge ? .increased : .standard)
                .preferredColorScheme(isDark ? .dark : .light))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
            window.frame = UIScreen.main.bounds
            let parent = UIViewController(); window.rootViewController = parent; window.makeKeyAndVisible()
            parent.addChild(host); parent.view.addSubview(host.view)
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: 844); host.didMove(toParent: parent)
            try await Task.sleep(nanoseconds: 500_000_000)
            host.view.layoutIfNeeded()
            XCTAssertEqual(host.view.bounds.width, width, accuracy: 1)
            let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image)
            attachment.name = "release117-hero-\(Int(width))-\(isDark ? "dark" : "light")-\(isLarge ? "large-contrast" : "normal")"
            attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true
        }
    }

    private func makeBook() -> BookshelfBook {
        BookshelfBook(id: "hero-fixture", title: "云朵邮局 · 写给远方的一封长信", author: "阅读样本",
                     coverURL: nil, sourceName: "本地", sourceURL: "local://text", bookURL: "local://hero", intro: nil)
    }
    @MainActor private func measure(type: DynamicTypeSize) -> CGSize {
        UIHostingController(rootView: ReadingHeroCard(book: makeBook()).environment(\.dynamicTypeSize, type))
            .sizeThatFits(in: CGSize(width: 288, height: 6000))
    }
    private func makeCover(_ colour: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 88, height: 128), format: format).image { context in
            colour.setFill(); context.fill(CGRect(x: 0, y: 0, width: 88, height: 128))
        }
    }
}
