import XCTest
import SwiftUI
import UIKit
@testable import SourceReadSwift

final class AppLayoutDensityTests: XCTestCase {
    func testChromeMetricsRemoveWhitespaceNotTapTargets() {
        XCTAssertEqual(AppLayout.pageMargin, 16)
        XCTAssertEqual(AppLayout.cardInset, 12)
        XCTAssertEqual(AppLayout.sectionGap, 14)
        XCTAssertGreaterThanOrEqual(AppLayout.minimumTapTarget, 44)
        XCTAssertEqual(AppLayout.minimumTapTarget + AppLayout.tabVerticalInset * 2, 54)
    }

    @MainActor func testSharedCardHasOnlyOneTwelvePointInset() {
        let host = UIHostingController(rootView: Color.clear.frame(width: 100, height: 40).podcastCard())
        let size = host.sizeThatFits(in: CGSize(width: 400, height: 1000))
        XCTAssertEqual(size.width, 124, accuracy: 1)
        XCTAssertEqual(size.height, 64, accuracy: 1)
    }

    @MainActor func testContinueCardIsContentSizedOnNarrowPhone() {
        let size = measureCard(width: 288, type: .large)
        XCTAssertEqual(size.width, 288, accuracy: 1)
        XCTAssertGreaterThanOrEqual(size.height, 100)
        XCTAssertLessThan(size.height, 160, "Normal text must not keep the previous 190pt promotional height")
    }

    @MainActor func testContinueCardGrowsForAccessibilityInsteadOfClipping() {
        let regular = measureCard(width: 288, type: .large)
        let accessible = measureCard(width: 288, type: .accessibility3)
        XCTAssertEqual(accessible.width, 288, accuracy: 1)
        XCTAssertGreaterThan(accessible.height, regular.height)
    }

    @MainActor func testMainPageRenderEvidence() async throws {
        let app = AppState()
        try await snapshot("home-390", width: 390, height: 844,
                           content: RootTabView(appState: app).environmentObject(app))
        try await snapshot("settings-390", width: 390, height: 844,
                           content: SettingsView().environmentObject(app))
        try await snapshot("sources-390", width: 390, height: 844,
                           content: NavigationStack { SourceManagerView() }.environmentObject(app))
    }

    @MainActor func testNarrowPageRenderEvidence() async throws {
        let app = AppState()
        try await snapshot("home-320", width: 320, height: 568,
                           content: RootTabView(appState: app).environmentObject(app))
        try await snapshot("settings-320", width: 320, height: 568,
                           content: SettingsView().environmentObject(app))
        try await snapshot("sources-320", width: 320, height: 568,
                           content: NavigationStack { SourceManagerView() }.environmentObject(app))
    }

    @MainActor func testDarkAndLargeTextRenderEvidence() async throws {
        let app = AppState()
        try await snapshot("settings-dark", width: 390, height: 844, style: .dark,
                           content: SettingsView().environmentObject(app).preferredColorScheme(.dark))
        try await snapshot("settings-accessibility", width: 390, height: 844,
                           content: SettingsView().environmentObject(app).environment(\.dynamicTypeSize, .accessibility3))
        try await snapshot("sources-accessibility", width: 390, height: 844,
                           content: NavigationStack { SourceManagerView() }.environmentObject(app)
                            .environment(\.dynamicTypeSize, .accessibility3))
    }

    @MainActor func testSourceOrganizationRenderEvidence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SourceStore(persistence: SourcePersistence(rootURL: root))
        let sources = (1...6).map { BookSource(bookSourceName: "示例书源 \($0)", bookSourceUrl: "https://source\($0).example", bookSourceGroup: "小说") }
        try store.importSources(sources)
        store.setPlacement(.top, for: [sources[0].id])
        store.setPlacement(.bottom, for: [sources[5].id])
        store.setGroup("收藏", for: [sources[0].id])
        try await snapshot("source-organization", width: 390, height: 844, content: SourceOrganizationView(store: store))
    }

    @MainActor private func measureCard(width: CGFloat, type: DynamicTypeSize) -> CGSize {
        let host = UIHostingController(rootView:
            ContinueReadingCardContent(title: "纸间 · 阅读指引与经典选篇", author: "纸间团队", progressText: "已读 35%") {
                Color.gray.frame(width: 54, height: 76)
            }.environment(\.dynamicTypeSize, type))
        return host.sizeThatFits(in: CGSize(width: width, height: 4000))
    }

    // Mounted UIKit rendering captures real List/NavigationStack layout and
    // materials. Attachments are exported by both CI SDK/runtime jobs.
    @MainActor private func snapshot<Content: View>(_ name: String, width: CGFloat, height: CGFloat,
                                                   style: UIUserInterfaceStyle = .light,
                                                   content: Content) async throws {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = UIScreen.main.bounds
        window.overrideUserInterfaceStyle = style
        let container = UIViewController()
        let host = UIHostingController(rootView: content)
        host.overrideUserInterfaceStyle = style
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.addChild(host)
        container.view.addSubview(host.view)
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        host.didMove(toParent: container)
        defer { window.isHidden = true }
        try await Task.sleep(nanoseconds: 350_000_000)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        XCTAssertEqual(host.view.bounds.width, width, accuracy: 1)
        XCTAssertEqual(host.traitCollection.userInterfaceStyle, style, "A hosted child must actually receive the requested appearance")
        let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        XCTAssertNotNil(image.pngData())
        let attachment = XCTAttachment(image: image)
        attachment.name = "density-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
