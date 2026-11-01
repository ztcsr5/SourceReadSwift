import XCTest
import SwiftUI
import UIKit
@testable import SourceReadSwift

final class TabChromeRegressionTests: XCTestCase {
    @MainActor func testOwnersCannotRevealChromeWhileAnotherReaderOwnsIt() {
        let app = AppState()
        let gateway = UUID(), reader = UUID()
        app.acquireTabChromeHidden(owner: gateway)
        app.acquireTabChromeHidden(owner: reader)
        app.releaseTabChromeHidden(owner: reader)
        XCTAssertTrue(app.isTabChromeHidden)
        app.releaseTabChromeHidden(owner: gateway)
        XCTAssertFalse(app.isTabChromeHidden)
    }

    @MainActor func testNativeRootHasNoEmptyAccessoryAndHonorsVisibilityOwner() async throws {
        #if compiler(>=6.2)
        guard #available(iOS 26.0, *) else { throw XCTSkip("Requires iOS26 runtime") }
        let app = AppState()
        let window = host(RootTabView().environmentObject(app))
        defer { window.isHidden = true }
        let ready = await eventually { self.tabs(in: window.rootViewController) != nil }
        XCTAssertTrue(ready)
        let tabs = try XCTUnwrap(self.tabs(in: window.rootViewController))
        let labelsReady = await eventually { tabs.tabBar.items?.count == 3 }
        XCTAssertTrue(labelsReady)
        XCTAssertEqual(tabs.tabBar.items?[1].title, AppNavigationLabels.findBooks)
        XCTAssertNil(tabs.bottomAccessory, "No playback must not create a blank glass accessory")
        let owner = UUID()
        app.acquireTabChromeHidden(owner: owner)
        let hidden = await eventually { tabs.isTabBarHidden }
        XCTAssertTrue(hidden, "Active child must receive the hidden preference")
        XCTAssertTrue(tabs === self.tabs(in: window.rootViewController), "Visibility cannot replace the TabView/navigation tree")
        app.releaseTabChromeHidden(owner: owner)
        let restored = await eventually { !tabs.isTabBarHidden }
        XCTAssertTrue(restored)
        XCTAssertNil(tabs.bottomAccessory)
        #else
        throw XCTSkip("Requires Xcode26 SDK")
        #endif
    }

    @MainActor func testNativePushedReaderHidesTabsAndPopRestoresThem() async throws {
        #if compiler(>=6.2)
        guard #available(iOS 26.0, *) else { throw XCTSkip("Requires iOS26 runtime") }
        let app = AppState(), route = TabChromeTestRoute()
        let window = host(TabChromeNavigationFixture(route: route).environmentObject(app))
        defer { window.isHidden = true }
        let ready = await eventually { route.isRootMounted && self.tabs(in: window.rootViewController) != nil }
        XCTAssertTrue(ready)
        let tabs = try XCTUnwrap(self.tabs(in: window.rootViewController))
        route.path = [1]
        _ = await eventually { tabs.isTabBarHidden && app.isTabChromeHidden }
        XCTAssertTrue(app.isTabChromeHidden, "Pushed destination must acquire the visibility owner")
        XCTAssertTrue(tabs.isTabBarHidden, "Pushed hideRootTabBar destination must hide the real native tab bar")
        route.path = []
        let restored = await eventually { !tabs.isTabBarHidden && !app.isTabChromeHidden }
        XCTAssertTrue(restored, "Popping must restore navigation rather than leave it permanently hidden")
        #else
        throw XCTSkip("Requires Xcode26 SDK")
        #endif
    }

    @MainActor private func host<Content: View>(_ content: Content) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = UIScreen.main.bounds
        window.rootViewController = UIHostingController(rootView: content)
        window.makeKeyAndVisible()
        return window
    }

    @MainActor private func tabs(in controller: UIViewController?) -> UITabBarController? {
        guard let controller else { return nil }
        if let tabs = controller as? UITabBarController { return tabs }
        for child in controller.children {
            if let tabs = tabs(in: child) { return tabs }
        }
        return nil
    }

    @MainActor private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }
}

private final class TabChromeTestRoute: ObservableObject {
    @Published var path: [Int] = []
    @Published var isRootMounted = false
}

private struct TabChromeNavigationFixture: View {
    @ObservedObject var route: TabChromeTestRoute
    var body: some View {
        TabView {
            NavigationStack(path: $route.path) {
                Text("Home")
                    .onAppear { route.isRootMounted = true }
                    .navigationDestination(for: Int.self) { _ in
                        Text("Reader").hideRootTabBar()
                    }
            }
            // Use the same owner-driven policy as RootTabView; a permanently
            // visible test root does not model the production navigation tree.
            .modifier(RootTabChromeVisibilityModifier())
            .tabItem { Label("Home", systemImage: "house") }
            Text("Settings").tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
