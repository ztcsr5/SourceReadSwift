import UIKit
import XCTest
@testable import SourceReadSwift

final class HomeScreenIconAlignmentTests: XCTestCase {
    @MainActor
    func testContainerSelectsTheExportArtworkWithoutSendingUIKitARequest() async throws {
        let suite = "ContainerIconChoice.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: PersonalBrandMarkStore.enabledKey)
        var attempts = 0
        let manager = AppIconManager(defaults: defaults, systemIcon: .init(
            isSupported: { true }, currentName: { nil },
            setName: { _ in attempts += 1 }, isDeclared: { _ in false }, isContainer: { true }))
        let selected = await manager.select(.wuxia)
        XCTAssertTrue(selected)
        XCTAssertEqual(attempts, 0)
        XCTAssertEqual(manager.currentOption, .wuxia)
        XCTAssertEqual(manager.homeScreenShortcutSuggestion, .wuxia)
        XCTAssertFalse(defaults.bool(forKey: PersonalBrandMarkStore.enabledKey))
        XCTAssertTrue(manager.statusMessage?.contains("不会自动更新") == true)
        manager.syncFromUIKitIfNeeded()
        XCTAssertEqual(manager.currentOption, .wuxia)
    }

    func testOnlyParsesExplicitGuestLaunchURLs() {
        let link = "livecontainer2://livecontainer-launch?bundle-name=PaperBetween.app&container-folder-name=fixture"
        XCTAssertEqual(LiveContainerLaunchLink.url(from: " \(link)\n")?.absoluteString, link)
        for other in [
            "https://host.invalid/?bundle-name=PaperBetween.app",
            "livecontainer://open-web-page?bundle-name=PaperBetween.app",
            "livecontainer://livecontainer-launch?bundle-name=ui",
            "livecontainer://livecontainer-launch?bundle-name=a&bundle-name=b",
            "livecontainer://livecontainer-launch?bundle-name=a&container-folder-name=..%2Fprivate"
        ] {
            XCTAssertNil(LiveContainerLaunchLink.url(from: other))
        }
    }

    @MainActor
    func testPhotoExportPreservesThePreviewMatte() throws {
        let original = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        let full = PersonalBrandMarkStore.shortcutIcon(from: original, frame: .full)
        let matte = PersonalBrandMarkStore.shortcutIcon(from: original, frame: .matte)
        XCTAssertEqual(matte.size, CGSize(width: 512, height: 512))
        XCTAssertEqual(matte.scale, 1)
        XCTAssertNotEqual(try XCTUnwrap(matte.pngData()), try XCTUnwrap(full.pngData()))
        XCTAssertGreaterThan(PersonalBrandMarkStore.Frame.matte.insetFraction, 0)
    }
}
