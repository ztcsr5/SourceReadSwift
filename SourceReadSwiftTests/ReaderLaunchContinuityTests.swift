import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

@MainActor
final class ReaderLaunchContinuityTests: XCTestCase {
    func testPackagedLaunchColorExistsAndMatchesTheDefaultHomeInBothAppearances() throws {
        let launch = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen") as? [String: Any])
        let name = try XCTUnwrap(launch["UIColorName"] as? String)
        let color = try XCTUnwrap(UIColor(named: name), "The installed app must contain the named launch asset")
        let theme = AppVisualTheme.initialSelection
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let expected = AppVisualTheme.uiColor(style == .dark ? theme.darkBackgroundHex : theme.backgroundHex)
            assertSameColor(color.resolvedColor(with: traits), expected)
            assertSameColor(ReaderLaunchSurface.color.resolvedColor(with: traits), expected)
        }
    }

    func testColdLaunchKeepsReadyHomeVisibleWithoutWaitingForAppearanceCallbacks() {
        let home = UIViewController()
        home.loadViewIfNeeded()
        let navigation = ReaderNavigationController(rootViewController: home)
        navigation.loadViewIfNeeded()
        navigation.stageLaunchReveal(for: home.view)
        XCTAssertEqual(home.view.alpha, 1, "A container may delay viewDidAppear; do not suppress a ready first frame")
        XCTAssertTrue(home.view.isUserInteractionEnabled)
        XCTAssertTrue(home.view.transform.isIdentity)
        navigation.viewDidAppear(false)
        XCTAssertEqual(home.view.alpha, 1)
        XCTAssertTrue(home.view.isUserInteractionEnabled)
        XCTAssertTrue(home.view.transform.isIdentity)
    }

    func testMountedRootHasTheSameOpaqueBackingBeforeAndAfterAnAppearanceChange() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let root = UIHostingController(rootView: ReaderNavigationHost().ignoresSafeArea().environmentObject(AppState()))
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }

        for _ in 0..<100 where findNavigation(in: root) == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let navigation = try XCTUnwrap(findNavigation(in: root))
        let home = try XCTUnwrap(navigation.viewControllers.first)
        for style in [UIUserInterfaceStyle.light, .dark] {
            window.overrideUserInterfaceStyle = style
            window.layoutIfNeeded()
            let expected = ReaderLaunchSurface.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            for surface in [window, navigation.view!, home.view!] {
                let color = try XCTUnwrap(surface.backgroundColor)
                let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
                assertSameColor(resolved, expected)
                XCTAssertEqual(resolved.cgColor.alpha, 1)
            }
        }
    }

    private func findNavigation(in controller: UIViewController) -> ReaderNavigationController? {
        if let navigation = controller as? ReaderNavigationController { return navigation }
        for child in controller.children {
            if let navigation = findNavigation(in: child) { return navigation }
        }
        return nil
    }

    private func assertSameColor(_ actual: UIColor, _ expected: UIColor, file: StaticString = #filePath, line: UInt = #line) {
        var actualRed: CGFloat = 0, actualGreen: CGFloat = 0, actualBlue: CGFloat = 0, actualAlpha: CGFloat = 0
        var expectedRed: CGFloat = 0, expectedGreen: CGFloat = 0, expectedBlue: CGFloat = 0, expectedAlpha: CGFloat = 0
        XCTAssertTrue(actual.getRed(&actualRed, green: &actualGreen, blue: &actualBlue, alpha: &actualAlpha), file: file, line: line)
        XCTAssertTrue(expected.getRed(&expectedRed, green: &expectedGreen, blue: &expectedBlue, alpha: &expectedAlpha), file: file, line: line)
        XCTAssertEqual(actualRed, expectedRed, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualGreen, expectedGreen, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualBlue, expectedBlue, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualAlpha, expectedAlpha, accuracy: 0.001, file: file, line: line)
    }
}
