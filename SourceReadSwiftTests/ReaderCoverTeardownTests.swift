import XCTest
import SwiftUI
import UIKit
@testable import SourceReadSwift

@MainActor
final class ReaderCoverTeardownTests: XCTestCase {
    private final class Events {
        var commits: [Int] = []
        var interactions: [Bool] = []
        var layouts = 0
        func clear() { commits = []; interactions = []; layouts = 0 }
        var count: Int { commits.count + interactions.count + layouts }
    }

    private func apply(_ controller: CoverPageHostController, _ events: Events,
                       page: String = "p0", next: String = "p1", style: CoverPageTurnStyle = .cover) {
        controller.apply(pageIdentity: page, contentRevision: "layout",
                         previousIdentity: "previous", currentIdentity: page, nextIdentity: next,
                         hasPrevious: true, hasNext: true,
                         previous: AnyView(Color.red), current: AnyView(Color.green), next: AnyView(Color.blue),
                         onCommit: { events.commits.append($0) },
                         onInteractionChange: { events.interactions.append($0) },
                         onPageContainerLayout: { _, _ in events.layouts += 1 }, turnStyle: style)
    }

    private func makeController(_ events: Events, style: CoverPageTurnStyle = .cover) -> CoverPageHostController {
        let controller = CoverPageHostController()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        apply(controller, events, style: style)
        return controller
    }

    private func drain() async {
        for _ in 0..<3 {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    private func dismantle(_ controller: CoverPageHostController) {
        let coordinator = ()
        CoverPageReaderView.dismantleUIViewController(controller, coordinator: coordinator)
    }

    func testActualDismantleNeverPublishesSynchronously() {
        let events = Events(), controller = makeController(Events())
        apply(controller, events)
        events.clear()
        dismantle(controller)
        XCTAssertEqual(events.count, 0, "Publishing here re-enters SwiftUI's exclusively borrowed graph on iOS 17")
    }

    func testActiveDragDismantleDoesNotSendInteractionEnd() async {
        for style in [CoverPageTurnStyle.cover, .slide] {
            let events = Events(), controller = makeController(events, style: style)
            controller.beginInteraction()
            controller.updateInteraction(translation: -180)
            XCTAssertTrue(controller.isDragging)
            events.clear()
            dismantle(controller)
            XCTAssertFalse(controller.isDragging)
            XCTAssertEqual(events.count, 0)
            await drain()
            XCTAssertEqual(events.count, 0)
        }
    }

    func testPendingSnapshotIsNotInstalledDuringDismantle() async {
        let events = Events(), controller = makeController(events)
        controller.beginInteraction()
        apply(controller, events, next: "replacement")
        XCTAssertEqual(controller.installedPageKeys[3], "p1")
        let children = controller.children.map(ObjectIdentifier.init)
        dismantle(controller)
        await drain()
        XCTAssertEqual(controller.installedPageKeys[3], "p1")
        XCTAssertEqual(controller.children.map(ObjectIdentifier.init), children)
    }

    func testQueuedTapAndIdleCallbacksAreDroppedAfterDismantle() async {
        let events = Events(), controller = makeController(events)
        controller.requestTurn(ReaderPageTurnRequest(direction: 1))
        events.clear()
        dismantle(controller)
        await drain()
        XCTAssertEqual(events.count, 0)
        XCTAssertEqual(controller.visiblePageIdentity, "p0")
    }

    func testQueuedSecondFlickCannotCommitAfterDismantle() async {
        let events = Events(), controller = makeController(events)
        for _ in 0..<2 {
            controller.beginInteraction()
            controller.updateInteraction(translation: -180)
            controller.endInteraction(velocity: -500, animated: false)
        }
        XCTAssertEqual(events.commits, [1])
        apply(controller, events, page: "p1", next: "p2")
        dismantle(controller)
        await drain()
        XCTAssertEqual(events.commits, [1])
    }

    func testRunningAnimationCannotCommitAfterDismantle() async throws {
        let events = Events(), controller = makeController(events)
        controller.beginInteraction()
        controller.updateInteraction(translation: -180)
        controller.endInteraction(velocity: -500)
        events.clear()
        dismantle(controller)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(events.count, 0)
    }

    func testTerminalControllerRejectsAllLaterEntryPoints() async {
        let events = Events(), controller = makeController(events)
        dismantle(controller)
        dismantle(controller)
        events.clear()
        apply(controller, events, page: "late", next: "late-next")
        controller.beginInteraction()
        controller.updateInteraction(translation: -180)
        controller.endInteraction(velocity: -500, animated: false)
        controller.cancelInteraction()
        controller.requestTurn(ReaderPageTurnRequest(direction: 1))
        controller.view.frame.size.width = 400
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        await drain()
        XCTAssertEqual(events.count, 0)
        XCTAssertEqual(controller.visiblePageIdentity, "p0")
        XCTAssertFalse(controller.isDragging)
        XCTAssertTrue(controller.view.gestureRecognizers?.allSatisfy { !$0.isEnabled } == true)
    }

    func testDismantleReleasesCallbackCapturesImmediately() async {
        var events: Events? = Events()
        weak var captured = events
        let controller = makeController(events!)
        events = nil
        XCTAssertNotNil(captured)
        dismantle(controller)
        XCTAssertNil(captured, "Queued work must not retain stale reader callback captures")
        await drain()
        _ = controller
    }

    func testNormalCancelRemainsReusableAndCommitsExactlyOnce() async {
        let events = Events(), controller = makeController(events)
        controller.beginInteraction()
        controller.updateInteraction(translation: -180)
        controller.cancelInteraction()
        await drain()
        XCTAssertEqual(events.interactions.last, false)
        XCTAssertTrue(events.commits.isEmpty)
        controller.beginInteraction()
        controller.updateInteraction(translation: -180)
        controller.endInteraction(velocity: -500, animated: false)
        XCTAssertEqual(events.commits, [1])
        dismantle(controller)
    }

    func testResizeCancelPublishesOnlyAfterLayoutTransaction() async {
        let events = Events(), controller = makeController(events)
        await drain()
        controller.beginInteraction()
        events.clear()
        controller.view.frame.size.width = 400
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        XCTAssertEqual(events.count, 0)
        await drain()
        XCTAssertEqual(events.interactions.last, false)
        XCTAssertGreaterThan(events.layouts, 0)
        dismantle(controller)
    }

    func testDeferredCancelCannotEndANewerDrag() async {
        let events = Events(), controller = makeController(events)
        controller.cancelInteraction()
        controller.beginInteraction()
        await drain()
        XCTAssertEqual(events.interactions, [true])
        XCTAssertTrue(controller.isDragging)
        dismantle(controller)
    }

    private final class MountState: ObservableObject {
        @Published var visible = true
        var lateCallbacks = 0
        func callback() { if !visible { lateCallbacks += 1 } }
    }

    private struct MountFixture: View {
        @ObservedObject var state: MountState
        var body: some View {
            if state.visible {
                CoverPageReaderView(pageIdentity: "p0", contentRevision: "layout", currentIdentity: "p0",
                    hasPrevious: false, hasNext: false, previous: nil, current: AnyView(Color.white), next: nil,
                    previous2: nil, next2: nil, onCommit: { _ in state.callback() },
                    onInteractionChange: { _ in state.callback() }, onPageContainerLayout: { _, _ in state.callback() })
            } else { Color.clear }
        }
    }

    private func findPager(_ controller: UIViewController) -> CoverPageHostController? {
        if let pager = controller as? CoverPageHostController { return pager }
        return controller.children.lazy.compactMap { findPager($0) }.first
    }

    func testSwiftUIUnmountUsesSilentTerminalPath() async throws {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = UIScreen.main.bounds
        let state = MountState()
        let host = UIHostingController(rootView: MountFixture(state: state))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for _ in 0..<100 {
            if findPager(host) != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let pager = try XCTUnwrap(findPager(host))
        await drain()
        pager.beginInteraction()
        pager.updateInteraction(translation: -80)
        state.visible = false
        for _ in 0..<100 {
            if findPager(host) == nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNil(findPager(host))
        await drain()
        XCTAssertEqual(state.lateCallbacks, 0)
        XCTAssertFalse(pager.isDragging)
    }
}
