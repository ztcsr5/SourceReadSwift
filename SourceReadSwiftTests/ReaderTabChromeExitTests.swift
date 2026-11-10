import SwiftUI
import XCTest
import UIKit
import Combine
@testable import SourceReadSwift

/// 覆盖层路径下的 tab chrome 契约。
///
/// 新契约（为消除"一滑就浮现/闪一下"而刻意更改）：
/// 1. 转场开始**不**释放所有权，底栏必须继续隐藏；
/// 2. 最后一个 owner 释放后进入 350ms 挂起窗口，窗口内不得提前暴露底栏；
/// 3. 窗口内若重新 acquire（手势取消），取消挂起，底栏保持隐藏；
/// 4. 只有真正提交且窗口结束，才显示底栏。
///
/// 旧断言要求"释放早于 onDisappear"，那正是闪动的成因，已被替换。
final class ReaderTabChromeExitTests: XCTestCase {
    @MainActor func testInteractivePopIsRecognizedBeforeTheSourceLeavesTheStack() {
        let root = UIViewController(), reader = UIViewController(), pushed = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.pushViewController(reader, animated: false)
        XCTAssertTrue(ReaderNativePopPolicy.isPop(from: reader, to: root, in: navigation, isInteractive: true))
        XCTAssertFalse(ReaderNativePopPolicy.isPop(from: reader, to: pushed, in: navigation, isInteractive: true))
        XCTAssertFalse(ReaderNativePopPolicy.isPop(from: reader, to: pushed, in: navigation, isInteractive: false))
    }

    @MainActor func testRealUIKitPopKeepsOwnershipUntilThePopCommits() async throws {
        let app = AppState(), owner = UUID()
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = UIScreen.main.bounds
        let navigation = UINavigationController(rootViewController: UIViewController())
        window.rootViewController = navigation; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        let source = ReaderExitTimingHost()
        let host = UIHostingController(rootView: Color.clear
            .background(ReaderTabChromeExitBridge(owner: owner)).environmentObject(app))
        source.addChild(host); source.view.addSubview(host.view)
        host.view.frame = window.bounds; host.didMove(toParent: source)
        navigation.pushViewController(source, animated: false)
        for _ in 0..<50 {
            if source.hasAppeared && host.view.window != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(source.hasAppeared)
        XCTAssertNotNil(host.view.window)
        app.acquireTabChromeHidden(owner: owner)

        var disappearedWhenRevealed: Bool?
        let observation = app.$isTabChromeHidden.dropFirst().filter { !$0 }.prefix(1).sink { _ in
            disappearedWhenRevealed = source.hasDisappeared
        }
        defer { observation.cancel() }

        navigation.popViewController(animated: true)
        // 转场开始的一瞬间不得释放：源视图还在，底栏必须继续隐藏。
        XCTAssertTrue(app.isTabChromeHidden, "pop 开始时不能提前恢复底栏")

        let revealed = try await waitUntil { !app.isTabChromeHidden }
        XCTAssertTrue(revealed, "提交之后必须最终归还所有权")
        XCTAssertEqual(disappearedWhenRevealed, true, "归还必须发生在转场提交之后")

        for _ in 0..<50 {
            if source.hasDisappeared { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(source.hasDisappeared)
    }

    @MainActor func testLastOwnerReleaseIsHeldForTheSettleWindow() async throws {
        let app = AppState(), gateway = UUID(), reader = UUID()
        app.acquireTabChromeHidden(owner: gateway)
        app.acquireTabChromeHidden(owner: reader)
        XCTAssertTrue(app.isTabChromeHidden)

        app.releaseTabChromeHidden(owner: gateway)
        XCTAssertTrue(app.isTabChromeHidden, "还剩一个 owner 时必须继续隐藏")

        app.releaseTabChromeHidden(owner: reader)
        XCTAssertTrue(app.isTabChromeHidden, "挂起窗口内不得提前暴露底栏")

        // 窗口内重新取得（等价于手势取消）→ 取消挂起，底栏保持隐藏。
        app.acquireTabChromeHidden(owner: gateway)
        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertTrue(app.isTabChromeHidden, "取消返回必须保持沉浸，不能被挂起窗口提前放出来")

        app.releaseTabChromeHidden(owner: gateway)
        let revealed = try await waitUntil { !app.isTabChromeHidden }
        XCTAssertTrue(revealed, "没有任何 owner 之后必须最终显示底栏")
    }

    @MainActor func testRepeatedCallbacksDoNotReleaseUnrelatedOwnersOrRestoreACompletedExit() async throws {
        let app = AppState(), unrelated = UUID(), reader = UUID()
        let controller = ReaderTabChromeExitController()
        var releases = 0, restores = 0
        controller.configure(onLeaving: { releases += 1; app.releaseTabChromeHidden(owner: reader) },
            onCancelled: { restores += 1; app.acquireTabChromeHidden(owner: reader) })
        app.acquireTabChromeHidden(owner: unrelated); app.acquireTabChromeHidden(owner: reader)
        controller.prepareForExit(); controller.prepareForExit()
        XCTAssertEqual(releases, 1)
        XCTAssertTrue(app.isTabChromeHidden, "仍有无关 owner，必须继续隐藏")
        controller.finishExit(cancelled: false); controller.finishExit(cancelled: true)
        XCTAssertEqual(restores, 0, "已提交的退出不得被后续回调恢复")

        app.releaseTabChromeHidden(owner: unrelated)
        XCTAssertTrue(app.isTabChromeHidden, "挂起窗口内仍保持隐藏")
        let revealed = try await waitUntil { !app.isTabChromeHidden }
        XCTAssertTrue(revealed)
    }

    @MainActor private func waitUntil(timeout: TimeInterval = 2.5,
                                      _ condition: @escaping () -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }
}

private final class ReaderExitTimingHost: UIViewController {
    private(set) var hasAppeared = false
    private(set) var hasDisappeared = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        hasDisappeared = true
    }
}
