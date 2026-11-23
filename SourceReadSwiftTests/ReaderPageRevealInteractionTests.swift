import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

@MainActor
final class ReaderPageRevealInteractionTests: XCTestCase {
    func testInstantTurnKeepsPageStillAndCommitsOnceWithoutAnAnimator() async throws {
        let reader = try MountedReader(style: .instant)
        defer { reader.close() }
        let current = try reader.page(2)
        let next = try reader.page(3)
        let originalFrame = current.frame
        reader.controller.beginInteraction()
        reader.controller.updateInteraction(translation: -160)
        XCTAssertEqual(current.frame, originalFrame)
        XCTAssertTrue(next.isHidden)
        reader.controller.endInteraction(velocity: 0, cancelled: true)
        XCTAssertTrue(reader.commits.isEmpty)
        XCTAssertNil(reader.controller.animator)
        reader.controller.beginInteraction()
        reader.controller.updateInteraction(translation: -160)
        reader.controller.endInteraction(velocity: -2_000)
        XCTAssertEqual(reader.commits, [1]); XCTAssertNil(reader.controller.animator)
        reader.install(index: 3)
        XCTAssertFalse(try reader.page(3).isHidden)
        reader.controller.requestTurn(.init(direction: -1))
        await Task.yield()
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(reader.commits, [1, -1]); XCTAssertNil(reader.controller.animator)
    }

    func testProgrammaticTurnsPrepareBothDirectionsBeforeTheAnimatedMidpoint() async throws {
        for style in [CoverPageTurnStyle.dissolve, .stacked, .ripple] {
            for direction in [-1, 1] {
                let reader = try MountedReader(style: style)
                defer { reader.close() }
                // Leave the previously selected reveal direction opposite to the tap.
                reader.controller.beginInteraction()
                reader.controller.updateInteraction(translation: CGFloat(direction) * 50)
                reader.controller.endInteraction(velocity: 0, cancelled: true, animated: false)
                reader.controller.requestTurn(ReaderPageTurnRequest(direction: direction))
                let animation = try await waitForAnimation(reader.controller)
                XCTAssertEqual(animation.duration, style == .stacked ? 0.36 : 0.44, accuracy: 0.001,
                               "A requested turn must use its explicit motion duration")
                animation.pauseAnimation()
                animation.fractionComplete = 0.5
                try await flushPresentation()

                let incoming = try reader.page(2 + direction)
                let current = try reader.page(2)
                try assertIntermediateReveal(style: style, incoming: incoming, direction: direction,
                                             width: reader.controller.view.bounds.width)
                XCTAssertNil(current.mask)
                assertAccessibleCurrent(current, neighbours: [incoming])
                assertHitReachesCurrent(reader.controller.view, current: current)

                finish(animation)
                XCTAssertEqual(reader.commits, [direction])
                reader.install(index: 2 + direction)
                XCTAssertEqual(reader.controller.visiblePageIdentity, "p\(2 + direction)")
                XCTAssertNil(incoming.mask)
                XCTAssertTrue(incoming.isUserInteractionEnabled)
                XCTAssertFalse(incoming.accessibilityElementsHidden)
            }
        }
    }

    func testAnimatedShortDragCancellationPreservesCurrentAndDirection() async throws {
        for style in [CoverPageTurnStyle.dissolve, .stacked, .ripple] {
            for direction in [-1, 1] {
                let reader = try MountedReader(style: style)
                defer { reader.close() }
                let current = try reader.page(2)
                let incoming = try reader.page(2 + direction)
                reader.controller.beginInteraction()
                reader.controller.updateInteraction(translation: -CGFloat(direction) * 60)
                let originalMask = incoming.mask
                reader.controller.endInteraction(velocity: 0, cancelled: true)
                let animation = try XCTUnwrap(reader.controller.animator)
                animation.pauseAnimation()
                animation.fractionComplete = 0.5
                try await flushPresentation()
                XCTAssertTrue(reader.commits.isEmpty)
                XCTAssertNil(current.mask)
                if style == .ripple { XCTAssertTrue(incoming.mask === originalMask) }
                finish(animation)
                XCTAssertEqual(reader.controller.visiblePageIdentity, "p2")
                XCTAssertEqual(current.transform, .identity)
                XCTAssertEqual(current.alpha, 1)
                assertAccessibleCurrent(current, neighbours: [incoming])
                assertHitReachesCurrent(reader.controller.view, current: current)
                XCTAssertTrue(reader.commits.isEmpty)
            }
        }
    }

    func testVelocityReversalClosesOldRevealBeforeOpeningTheOppositePage() async throws {
        for style in [CoverPageTurnStyle.stacked, .ripple] {
            let reader = try MountedReader(style: style)
            defer { reader.close() }
            let next = try reader.page(3)
            let previous = try reader.page(1)
            reader.controller.beginInteraction()
            reader.controller.updateInteraction(translation: -120)
            let originalMask = next.mask
            reader.controller.endInteraction(velocity: 3_000)
            let returning = try XCTUnwrap(reader.controller.animator)
            returning.pauseAnimation()
            returning.fractionComplete = 0.5
            try await flushPresentation()
            if style == .ripple {
                XCTAssertTrue(next.mask === originalMask, "Do not move a visible mask to the opposite page")
                XCTAssertNil(previous.mask)
                let layer = try XCTUnwrap(originalMask?.layer.presentation())
                XCTAssertGreaterThan(layer.transform.m11, 0)
                XCTAssertLessThan(layer.transform.m11, 120 / reader.controller.view.bounds.width)
            }
            XCTAssertTrue(reader.commits.isEmpty)

            finish(returning)
            let opening = try XCTUnwrap(reader.controller.animator)
            XCTAssertFalse(opening === returning)
            opening.pauseAnimation()
            opening.fractionComplete = 0.5
            try await flushPresentation()
            XCTAssertNil(next.mask)
            try assertIntermediateReveal(style: style, incoming: previous, direction: -1,
                                         width: reader.controller.view.bounds.width)
            finish(opening)
            XCTAssertEqual(reader.commits, [-1])
        }
    }

    func testNewDragFinishesAReversingRevealExactlyOnce() throws {
        let reader = try MountedReader(style: .ripple)
        defer { reader.close() }
        reader.controller.beginInteraction()
        reader.controller.updateInteraction(translation: -120)
        reader.controller.endInteraction(velocity: 3_000)
        XCTAssertNotNil(reader.controller.animator)
        reader.controller.beginInteraction()
        XCTAssertEqual(reader.commits, [-1])
        XCTAssertNil(reader.controller.animator, "An interrupted first segment must not leave a second animator running")
        reader.install(index: 1)
        reader.controller.updateInteraction(translation: 20)
        reader.controller.endInteraction(velocity: 0, cancelled: true, animated: false)
        XCTAssertEqual(reader.commits, [-1])
    }

    func testRippleFirstAndLastPagesRemoveThePreviousIncomingMask() async throws {
        for direction in [-1, 1] {
            let reader = try MountedReader(style: .ripple, index: 1, count: 3)
            defer { reader.close() }
            reader.controller.beginInteraction()
            reader.controller.updateInteraction(translation: -CGFloat(direction) * 160)
            reader.controller.endInteraction(velocity: 0)
            finish(try XCTUnwrap(reader.controller.animator))
            reader.install(index: 1 + direction)
            let current = try reader.page(1 + direction)
            XCTAssertNil(current.mask, "A terminal page has no incoming neighbour to take over the previous mask")
            XCTAssertEqual(current.transform, .identity)
            XCTAssertEqual(current.alpha, 1)
            assertAccessibleCurrent(current, neighbours: [try reader.page(1)])
            assertHitReachesCurrent(reader.controller.view, current: current)
            reader.controller.view.bounds.size.width += 80
            reader.controller.view.setNeedsLayout()
            reader.controller.view.layoutIfNeeded()
            XCTAssertNil(current.mask, "A terminal page must remain unclipped after viewport changes")
            reader.controller.requestTurn(ReaderPageTurnRequest(
                direction: direction, pageIdentity: "p2", style: .curl
            ))
            try await Task.sleep(nanoseconds: 10_000_000)
            XCTAssertEqual(reader.commits, [direction])
            XCTAssertNil(reader.controller.animator)
        }
    }

    func testCoverAndSlideKeepTheirSingleSegmentVelocityProjection() throws {
        for style in [CoverPageTurnStyle.cover, .slide] {
            let reader = try MountedReader(style: style)
            defer { reader.close() }
            reader.controller.beginInteraction()
            reader.controller.updateInteraction(translation: -120)
            reader.controller.endInteraction(velocity: -3_000)
            let animation = try XCTUnwrap(reader.controller.animator)
            XCTAssertGreaterThanOrEqual(animation.duration, 0.28,
                                        "A same-direction fast flick must retain its bounded silky release timing")
            XCTAssertLessThanOrEqual(animation.duration, 0.44,
                                     "A same-direction fast flick must retain its bounded release timing")
            finish(animation)
            XCTAssertEqual(reader.commits, [1])
            XCTAssertNil(reader.controller.animator)
        }
    }

    func testCurlFingerTurnUsesBoundedVelocityBasedReleaseTiming() async throws {
        let reader = try MountedReader(style: .curl)
        defer { reader.close() }
        try await Task.sleep(nanoseconds: 240_000_000)
        reader.controller.beginInteraction()
        reader.controller.updateInteraction(translation: -120)
        reader.controller.endInteraction(velocity: -3_000)
        let overlay = try await waitForCurlOverlay(reader.controller)
        let strip = try XCTUnwrap(overlay.subviews.first)
        let animation = try XCTUnwrap(strip.layer.animation(forKey: ReaderCurlSurface.foldAnimationKey) as? CAAnimationGroup)
        XCTAssertGreaterThanOrEqual(animation.duration, 0.34)
        XCTAssertLessThanOrEqual(animation.duration, 0.46)
        XCTAssertNil(reader.controller.animator, "A prewarmed curl swipe must stay on its Core Animation path")
    }

    func testQueuedTapIsDiscardedIfItsPageChangesBeforeDispatch() async throws {
        let reader = try MountedReader(style: .cover)
        defer { reader.close() }
        let request = ReaderPageTurnRequest(direction: 1, pageIdentity: "p2", style: .cover)

        reader.controller.requestTurn(request)
        reader.install(index: 3)
        try await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertTrue(reader.commits.isEmpty)
        XCTAssertFalse(request.claim(pageIdentity: "p2", style: .cover),
                       "A delivered stale tap must not replay when its page returns")
        reader.install(index: 2)
        reader.controller.requestTurn(request)
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(reader.commits.isEmpty)
    }

    func testEveryAddedModeAnimatesTapsAndCommitsOnlyAtCompletion() async throws {
        for style in [CoverPageTurnStyle.verticalSlide, .parallax, .wipe, .split, .perspective] {
            for direction in [-1, 1] {
                let reader = try MountedReader(style: style)
                defer { reader.close() }
                reader.controller.requestTurn(ReaderPageTurnRequest(direction: direction))
                let animation = try await waitForAnimation(reader.controller)
                let expectedDuration: TimeInterval = (style == .verticalSlide || style == .parallax) ? 0.36 : 0.44
                XCTAssertEqual(animation.duration, expectedDuration, accuracy: 0.001)
                animation.pauseAnimation()
                animation.fractionComplete = 0.5
                try await flushPresentation()
                XCTAssertTrue(reader.commits.isEmpty, "Do not change the page cursor before its animation completes")
                let incoming = try reader.page(2 + direction)
                let layer = try XCTUnwrap((incoming.mask ?? incoming).layer.presentation())
                if style == .wipe || style == .split {
                    XCTAssertGreaterThan(layer.bounds.width, 1)
                    XCTAssertLessThan(layer.bounds.width, reader.controller.view.bounds.width - 1)
                } else {
                    XCTAssertFalse(CATransform3DIsIdentity(layer.transform))
                }
                finish(animation)
                XCTAssertEqual(reader.commits, [direction])
                reader.install(index: 2 + direction)
                let current = try reader.page(2 + direction)
                XCTAssertEqual(current.alpha, 1)
                XCTAssertTrue(current.isUserInteractionEnabled)
                XCTAssertNil(current.mask)
                XCTAssertTrue(CATransform3DIsIdentity(current.layer.transform))
            }
        }
    }

    func testVisiblePageIdentityPublishesOnlyAfterUIKitInstallsTheTargetSnapshot() async throws {
        let reader = try MountedReader(style: .cover)
        defer { reader.close() }
        try await flushPresentation()
        reader.installedIdentities.removeAll()

        reader.controller.requestTurn(ReaderPageTurnRequest(direction: 1))
        finish(try await waitForAnimation(reader.controller))
        XCTAssertEqual(reader.commits, [1])
        XCTAssertTrue(reader.installedIdentities.isEmpty, "Cursor commit alone is not visible-page confirmation")

        reader.install(index: 3)
        try await flushPresentation()
        XCTAssertEqual(reader.installedIdentities, ["p3"])
    }

    func testColdCurlTapStartsTheFallbackWithoutSynchronousRasterization() async throws {
        let reader = try MountedReader(style: .curl)
        defer { reader.close() }

        reader.controller.requestTurn(ReaderPageTurnRequest(direction: 1))
        let animation = try await waitForAnimation(reader.controller)
        XCTAssertEqual(animation.duration, 0.42, accuracy: 0.001)
        XCTAssertEqual(reader.controller.visiblePageIdentity, "p2")
        XCTAssertTrue(reader.commits.isEmpty)
        finish(animation)
        XCTAssertEqual(reader.commits, [1])
    }

    func testPrewarmedCurlTapTurnsTheOuterEdgeBeforeTheSpineInBothDirections() async throws {
        for direction in [-1, 1] {
            let reader = try MountedReader(style: .curl)
            defer { reader.close() }
            // Allow the visible page and its forward neighbour to be captured while idle.
            try await Task.sleep(nanoseconds: 240_000_000)
            reader.controller.requestTurn(ReaderPageTurnRequest(direction: direction))
            let overlay = try await waitForCurlOverlay(reader.controller)
            XCTAssertEqual(overlay.bounds.size, reader.controller.view.bounds.size)
            XCTAssertTrue(reader.commits.isEmpty)
            let first = try XCTUnwrap(overlay.subviews.first)
            let last = try XCTUnwrap(overlay.subviews.last)
            let spine = direction == 1 ? first : last
            let edge = direction == 1 ? last : first
            XCTAssertEqual(spine.bounds.height, overlay.bounds.height)
            XCTAssertGreaterThan(edge.layer.zPosition, spine.layer.zPosition)
            let spineTransforms = try curlTransforms(of: spine)
            let edgeTransforms = try curlTransforms(of: edge)
            XCTAssertGreaterThan(spineTransforms.count, 2)
            let spineMidpoint = try XCTUnwrap(spineTransforms.dropFirst(spineTransforms.count / 2).first)
            let edgeMidpoint = try XCTUnwrap(edgeTransforms.dropFirst(edgeTransforms.count / 2).first)
            XCTAssertEqual(spineMidpoint.caTransform3DValue.m11, 1, accuracy: 0.001)
            XCTAssertLessThan(edgeMidpoint.caTransform3DValue.m11, 0)
            XCTAssertNil(reader.controller.animator, "The curl must have only the Core Animation clock")

            for _ in 0..<100 where reader.commits.isEmpty {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertEqual(reader.commits, [direction])
            reader.install(index: 2 + direction)
            let current = try reader.page(2 + direction)
            XCTAssertEqual(current.alpha, 1)
            XCTAssertTrue(current.isUserInteractionEnabled)
            XCTAssertNil(overlay.superview)
        }
    }

    func testResizingCancelsARunningCurlWithoutCommittingThePage() async throws {
        let reader = try MountedReader(style: .curl)
        defer { reader.close() }
        try await Task.sleep(nanoseconds: 240_000_000)
        reader.controller.requestTurn(ReaderPageTurnRequest(direction: 1))
        let overlay = try await waitForCurlOverlay(reader.controller)
        reader.controller.view.bounds.size.width -= 50
        reader.controller.viewDidLayoutSubviews()
        XCTAssertNil(overlay.superview)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(reader.controller.visiblePageIdentity, "p2")
        XCTAssertTrue(reader.commits.isEmpty, "Removing CA animations on resize must not fire a stale commit")
        let current = try reader.page(2)
        XCTAssertTrue(current.isUserInteractionEnabled)

        try await Task.sleep(nanoseconds: 240_000_000)
        reader.controller.requestTurn(ReaderPageTurnRequest(direction: 1))
        let resized = try await waitForCurlOverlay(reader.controller)
        XCTAssertEqual(resized.bounds.size, reader.controller.view.bounds.size)
    }

    func testCurlCancellationAndBoundaryDoNotExposeMissingPages() throws {
        let reader = try MountedReader(style: .curl, index: 0, count: 3)
        defer { reader.close() }
        let current = try reader.page(0)
        reader.controller.beginInteraction()
        reader.controller.updateInteraction(translation: 150)
        XCTAssertEqual(current.alpha, 1, "No previous page: keep the whole current page visible")
        reader.controller.endInteraction(velocity: 0, cancelled: true, animated: false)
        reader.controller.beginInteraction()
        reader.controller.updateInteraction(translation: -80)
        reader.controller.endInteraction(velocity: 0, cancelled: true, animated: false)
        XCTAssertTrue(reader.commits.isEmpty)
        XCTAssertEqual(current.alpha, 1)
        XCTAssertEqual(current.transform, .identity)
        XCTAssertTrue(current.isUserInteractionEnabled)
    }

    func testSwitchingFromPerspectiveClearsLayerAndViewTransforms() throws {
        let reader = try MountedReader(style: .perspective)
        defer { reader.close() }
        let current = try reader.page(2)
        let incoming = try reader.page(3)
        current.layer.transform = CATransform3DMakeRotation(0.5, 0, 1, 0)
        current.transform = CGAffineTransform(translationX: -40, y: 0)
        incoming.layer.transform = CATransform3DMakeRotation(-0.5, 0, 1, 0)
        XCTAssertFalse(CATransform3DIsIdentity(current.layer.transform))
        reader.reconfigure(style: .parallax)
        XCTAssertTrue(CATransform3DIsIdentity(current.layer.transform))
        XCTAssertEqual(current.transform, .identity)
        XCTAssertTrue(CATransform3DIsAffine(incoming.layer.transform),
                      "Parallax may translate the next page but must clear perspective")
        XCTAssertEqual(incoming.transform.tx, reader.controller.view.bounds.width, accuracy: 0.5,
                       "The next parallax page rests just outside the viewport")
    }

    private func waitForAnimation(_ controller: CoverPageHostController) async throws -> UIViewPropertyAnimator {
        for _ in 0..<100 {
            if let animation = controller.animator { return animation }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        return try XCTUnwrap(controller.animator, "Expected a native animated turn; CI must have Reduce Motion disabled")
    }

    private func waitForCurlOverlay(_ controller: CoverPageHostController) async throws -> UIView {
        for _ in 0..<100 {
            if let overlay = controller.view.subviews.last,
               overlay.subviews.first?.layer.animation(forKey: ReaderCurlSurface.foldAnimationKey) != nil {
                return overlay
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        return try XCTUnwrap(nil as UIView?, "Expected a full-sheet curl animation")
    }

    private func curlTransforms(of strip: UIView) throws -> [NSValue] {
        let animation = try XCTUnwrap(strip.layer.animation(forKey: ReaderCurlSurface.foldAnimationKey) as? CAAnimationGroup)
        XCTAssertEqual(animation.duration, 0.42, accuracy: 0.001)
        let transform = animation.animations?.compactMap { $0 as? CAKeyframeAnimation }.first { $0.keyPath == "transform" }
        return try XCTUnwrap(transform?.values as? [NSValue])
    }

    private func flushPresentation() async throws {
        CATransaction.flush()
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    private func finish(_ animation: UIViewPropertyAnimator) {
        animation.stopAnimation(false)
        animation.finishAnimation(at: .end)
    }

    private func assertIntermediateReveal(style: CoverPageTurnStyle, incoming: UIView, direction: Int, width: CGFloat) throws {
        switch style {
        case .stacked:
            let layer = try XCTUnwrap(incoming.layer.presentation())
            let offset = layer.transform.m41 * CGFloat(direction)
            XCTAssertGreaterThan(offset, 1, "A reverse tap must slide from outside the viewport, not fade at identity")
            XCTAssertLessThan(offset, width - 1)
            XCTAssertEqual(layer.opacity, 1, accuracy: 0.001)
        case .ripple:
            let mask = try XCTUnwrap(incoming.mask)
            let layer = try XCTUnwrap(mask.layer.presentation())
            XCTAssertGreaterThan(layer.transform.m11, 0.001)
            XCTAssertLessThan(layer.transform.m11, 0.999)
            XCTAssertEqual(layer.position.x, width * (direction < 0 ? 0.24 : 0.76), accuracy: 0.5)
        case .dissolve:
            let layer = try XCTUnwrap(incoming.layer.presentation())
            XCTAssertGreaterThan(layer.opacity, 0)
            XCTAssertLessThan(layer.opacity, 1)
        default:
            XCTFail("This assertion is only for reveal page styles")
        }
    }

    private func assertAccessibleCurrent(_ current: UIView, neighbours: [UIView]) {
        XCTAssertTrue(current.isUserInteractionEnabled)
        XCTAssertFalse(current.accessibilityElementsHidden)
        for neighbour in neighbours {
            XCTAssertFalse(neighbour.isUserInteractionEnabled)
            XCTAssertTrue(neighbour.accessibilityElementsHidden)
        }
    }

    private func assertHitReachesCurrent(_ container: UIView, current: UIView) {
        let hit = container.hitTest(CGPoint(x: container.bounds.midX, y: container.bounds.midY), with: nil)
        XCTAssertTrue(hit === current || hit?.isDescendant(of: current) == true,
                      "An invisible or masked neighbour must not intercept the current page's touch")
    }

    @MainActor
    private final class MountedReader {
        let controller = CoverPageHostController()
        let window: UIWindow
        let previousWindow: UIWindow?
        var style: CoverPageTurnStyle
        let count: Int
        private var currentIndex: Int
        var commits: [Int] = []
        var installedIdentities: [String] = []

        init(style: CoverPageTurnStyle, index: Int = 2, count: Int = 5) throws {
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            previousWindow = scene.windows.first(where: \.isKeyWindow)
            self.style = style
            self.count = count
            self.currentIndex = index
            window = UIWindow(windowScene: scene)
            window.frame = scene.screen.bounds
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            install(index: index)
            window.layoutIfNeeded()
            CATransaction.flush()
        }

        func install(index: Int) {
            currentIndex = index
            let hasPrevious = index > 0
            let hasNext = index + 1 < count
            controller.apply(pageIdentity: "p\(index)", contentRevision: "fixture",
                previousIdentity: hasPrevious ? "p\(index - 1)" : "", currentIdentity: "p\(index)",
                nextIdentity: hasNext ? "p\(index + 1)" : "", hasPrevious: hasPrevious, hasNext: hasNext,
                previous: hasPrevious ? root(index - 1) : nil, current: root(index), next: hasNext ? root(index + 1) : nil,
                onCommit: { [weak self] in self?.commits.append($0) }, onInteractionChange: { _ in },
                onPageInstalled: { [weak self] in self?.installedIdentities.append($0) },
                onPageContainerLayout: nil, turnStyle: style, pageBackgroundColor: .white)
        }

        func reconfigure(style: CoverPageTurnStyle) {
            self.style = style
            install(index: currentIndex)
        }

        func page(_ index: Int) throws -> UIView {
            let host = controller.children.first { $0.view.accessibilityIdentifier == "reader.page.p\(index)" }
            return try XCTUnwrap(host?.view)
        }

        func close() {
            controller.tearDown()
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }

        private func root(_ index: Int) -> AnyView {
            AnyView(Text("Page \(index)").frame(maxWidth: .infinity, maxHeight: .infinity))
        }
    }
}
