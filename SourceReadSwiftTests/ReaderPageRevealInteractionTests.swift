import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

@MainActor
final class ReaderPageRevealInteractionTests: XCTestCase {
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
            reader.controller.requestTurn(ReaderPageTurnRequest(direction: direction))
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
            reader.controller.endInteraction(velocity: 3_000)
            finish(try XCTUnwrap(reader.controller.animator))
            XCTAssertEqual(reader.commits, [-1])
            XCTAssertNil(reader.controller.animator)
        }
    }

    private func waitForAnimation(_ controller: CoverPageHostController) async throws -> UIViewPropertyAnimator {
        for _ in 0..<100 {
            if let animation = controller.animator { return animation }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        return try XCTUnwrap(controller.animator, "Expected a native animated turn; CI must have Reduce Motion disabled")
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
        let style: CoverPageTurnStyle
        let count: Int
        var commits: [Int] = []

        init(style: CoverPageTurnStyle, index: Int = 2, count: Int = 5) throws {
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            previousWindow = scene.windows.first(where: \.isKeyWindow)
            self.style = style
            self.count = count
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
            let hasPrevious = index > 0
            let hasNext = index + 1 < count
            controller.apply(pageIdentity: "p\(index)", contentRevision: "fixture",
                previousIdentity: hasPrevious ? "p\(index - 1)" : "", currentIdentity: "p\(index)",
                nextIdentity: hasNext ? "p\(index + 1)" : "", hasPrevious: hasPrevious, hasNext: hasNext,
                previous: hasPrevious ? root(index - 1) : nil, current: root(index), next: hasNext ? root(index + 1) : nil,
                onCommit: { [weak self] in self?.commits.append($0) }, onInteractionChange: { _ in },
                onPageContainerLayout: nil, turnStyle: style, pageBackgroundColor: .white)
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
