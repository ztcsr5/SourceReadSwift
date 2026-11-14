import SwiftUI
import XCTest
@testable import SourceReadSwift

/// Mounted home screens supplement the navigation tests with narrow, dark and large-text evidence.
final class HomeLayoutEvidenceTests: XCTestCase {
    private static let coreThemes: [AppVisualTheme] = [.forest, .classic, .kleinSage, .inkwash]
    private static let atmosphericThemes: [AppVisualTheme] = [.shuimo, .wuxia, .anime, .kawaii]
    private static let customThemes: [AppVisualTheme] = [.custom]

    func testHomeEvidenceGroupsCoverEveryRequestedThemeExactlyOnce() {
        let grouped = Self.coreThemes + Self.atmosphericThemes + Self.customThemes
        let expected = AppVisualTheme.allCases
        XCTAssertEqual(grouped.map(\.rawValue).sorted(), expected.map(\.rawValue).sorted())
        XCTAssertEqual(Set(grouped.map(\.rawValue)).count, grouped.count)
    }

    @MainActor func testCoreHomeLayoutsAtNarrowDarkAndAccessibleSizes() async throws {
        try await captureHomeLayouts(themes: Self.coreThemes)
    }

    @MainActor func testAtmosphericHomeLayoutsAtNarrowDarkAndAccessibleSizes() async throws {
        try await captureHomeLayouts(themes: Self.atmosphericThemes)
    }

    @MainActor func testCustomWorkshopHomeLayoutsAtNarrowDarkAndAccessibleSizes() async throws {
        try await captureHomeLayouts(themes: Self.customThemes)
    }

    // Keep the same screenshot matrix and assertions within the existing per-test time limit.
    @MainActor private func captureHomeLayouts(themes: [AppVisualTheme]) async throws {
        let defaults = UserDefaults.standard
        let keys = [AppVisualTheme.selectionKey, "settings.reducesMotion", "settings.floatingReadingDeskEnabled",
                    "settings.readingDeskEnabled", "bookshelf.isGridMode", "bookshelf.sortMode"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(true, forKey: "settings.readingDeskEnabled")
        defaults.set(true, forKey: "settings.reducesMotion")
        defaults.set(true, forKey: "bookshelf.isGridMode")
        defaults.set("最近阅读", forKey: "bookshelf.sortMode")
        let appState = FloatingDeskRegressionLaunch.makeAppState()
        XCTAssertEqual(appState.bookshelfStore.books.count, 3)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previousWindow = scene?.windows.first(where: \.isKeyWindow)
        defer { previousWindow?.makeKey() }
        // These attachments assess the settled layout. Cover loading is exercised separately.
        // A fixed 400 ms delay alone captured placeholders on the busier runner.
        let scale = scene?.screen.scale ?? UIScreen.main.scale
        let pixelSizes = [CGFloat(72), 108, 120, 132, 140, 156].map { $0 * max(scale, 1) }
            + [ReadingDeskCoverRaster.maximumPixelSize(points: 156, scale: scale)]
        for book in appState.bookshelfStore.books {
            guard let url = CoverURLResolver.url(from: book.coverURL, base: book.bookURL, fallbackBase: book.sourceURL) else { continue }
            for pixels in pixelSizes {
                let cover = await RemoteImageLoader.shared.image(for: url, maxPixelSize: pixels, reuseCoverBytes: true)
                XCTAssertNotNil(cover, "The local fixture must decode before assessing its jacket alignment")
            }
        }

        for theme in themes {
            defaults.set(theme.rawValue, forKey: AppVisualTheme.selectionKey)
            for (width, dark, accessible) in [(CGFloat(320), false, false), (390, true, false), (320, false, true)] {
                let screen = BookshelfView().environmentObject(appState)
                    .environment(\.dynamicTypeSize, accessible ? .accessibility3 : .large)
                    .preferredColorScheme(dark ? .dark : .light)
                let host = UIHostingController(rootView: screen)
                let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
                window.frame = UIScreen.main.bounds
                window.overrideUserInterfaceStyle = dark ? .dark : .light
                let parent = UIViewController()
                window.rootViewController = parent
                window.makeKeyAndVisible()
                parent.addChild(host)
                parent.view.addSubview(host.view)
                host.view.frame = CGRect(x: 0, y: 0, width: width, height: 844)
                host.didMove(toParent: parent)
                defer {
                    window.isHidden = true
                    host.willMove(toParent: nil)
                    host.view.removeFromSuperview()
                    host.removeFromParent()
                }
                try await Task.sleep(nanoseconds: 400_000_000)
                host.view.layoutIfNeeded()
                XCTAssertEqual(host.view.bounds.width, width, accuracy: 1)
                XCTAssertEqual(host.traitCollection.userInterfaceStyle, dark ? .dark : .light)
                let label = "home-audit-\(theme.rawValue)-\(Int(width))-\(dark ? "dark" : "light")-\(accessible ? "large-text" : "normal")-app-reduced-motion"
                attachLayout(host.view, name: label)
                if accessible { try await attachScrolledLayouts(host.view, name: label) }
            }
        }
    }

    @MainActor private func attachLayout(_ view: UIView, name: String) {
        let screenshot = UIGraphicsImageRenderer(size: view.bounds.size).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func attachScrolledLayouts(_ view: UIView, name: String) async throws {
        let scroll = try XCTUnwrap(verticalScrollView(in: view), "Large-text home must expose its offscreen shelf")
        for page in 1...8 {
            let bottom = max(-scroll.adjustedContentInset.top,
                             scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            if scroll.contentOffset.y >= bottom - 1 { break }
            let next = min(bottom, scroll.contentOffset.y + scroll.bounds.height * 0.75)
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: next), animated: false)
            try await Task.sleep(nanoseconds: 80_000_000)
            view.layoutIfNeeded()
            attachLayout(view, name: "\(name)-scroll-\(page)")
        }
        let bottom = max(-scroll.adjustedContentInset.top,
                         scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        XCTAssertGreaterThanOrEqual(scroll.contentOffset.y, bottom - 1, "Evidence must reach the final shelf row")
    }

    @MainActor private func verticalScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView,
           scroll.bounds.height > 0, scroll.contentSize.height > scroll.bounds.height + 1 {
            return scroll
        }
        for child in view.subviews {
            if let scroll = verticalScrollView(in: child) { return scroll }
        }
        return nil
    }

}
