import UIKit

/// iOS 16/17 compatibility uses UIKit's transition context and cancellation, never a timed unmount.
@MainActor
final class ReaderCompatibilityTransition: NSObject, UIViewControllerTransitioningDelegate, UIGestureRecognizerDelegate {
    let session: ReaderNavigationSession
    let source: () -> UIView?
    private(set) var interaction: UIPercentDrivenInteractiveTransition?
    private var beginReturn: () -> Void = {}
    private weak var gestureHost: UIView?
    private lazy var edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(track(_:)))

    init(session: ReaderNavigationSession, source: @escaping () -> UIView?) {
        self.session = session
        self.source = source
        super.init()
        edge.edges = .left
        edge.delegate = self
        edge.maximumNumberOfTouches = 1
    }

    func attach(to view: UIView, beginReturn: @escaping () -> Void) {
        detach()
        self.beginReturn = beginReturn
        gestureHost = view
        view.addGestureRecognizer(edge)
    }

    func detach() { edge.view?.removeGestureRecognizer(edge) }
    func didSettle() { interaction = nil }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        session.phase == .reading && session.allowsReturn && interaction == nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Content pans wait for the edge recognizer, preserving ordinary scrolling away from the edge.
        guard gestureRecognizer === edge, let host = gestureHost,
              let other = otherGestureRecognizer.view else { return false }
        return other.isDescendant(of: host)
    }

    @objc private func track(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard let host = gestureHost else { return }
        updateGesture(state: gesture.state, translation: gesture.translation(in: host),
                      velocity: gesture.velocity(in: host), width: host.bounds.width)
    }

    /// Routes recognized edge samples through UIKit's real interactive transition driver.
    func updateGesture(state: UIGestureRecognizer.State, translation: CGPoint, velocity: CGPoint, width: CGFloat) {
        let width = max(width, 1)
        switch state {
        case .began:
            let driver = UIPercentDrivenInteractiveTransition()
            driver.completionCurve = .easeOut
            interaction = driver
            beginReturn()
        case .changed:
            interaction?.update(min(max(translation.x / width, 0), 1))
        case .ended:
            let finish = translation.x > 0 && abs(translation.x) > abs(translation.y)
                && ReaderTransitionPolicy.shouldDismiss(translation: translation.x, velocity: velocity.x, width: width)
            if finish { interaction?.finish() } else { interaction?.cancel() }
        case .cancelled, .failed:
            interaction?.cancel()
        default: break
        }
    }

    func animator(isOpening: Bool) -> UIViewControllerAnimatedTransitioning {
        ReaderCompatibilityAnimator(isOpening: isOpening, source: source) { [weak self] in self?.didSettle() }
    }

    func animationController(forPresented presented: UIViewController, presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? { animator(isOpening: true) }
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        animator(isOpening: false)
    }
    func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        interaction
    }
    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?,
                                source: UIViewController) -> UIPresentationController? {
        ReaderFullScreenPresentation(presentedViewController: presented, presenting: presenting)
    }
}

private final class ReaderFullScreenPresentation: UIPresentationController {
    override var frameOfPresentedViewInContainerView: CGRect { containerView?.bounds ?? .zero }
    override var shouldRemovePresentersView: Bool { false }
}

private final class ReaderCompatibilityAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let isOpening: Bool
    let source: () -> UIView?
    let onComplete: () -> Void

    init(isOpening: Bool, source: @escaping () -> UIView?, onComplete: @escaping () -> Void) {
        self.isOpening = isOpening
        self.source = source
        self.onComplete = onComplete
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { 0.36 }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        guard let from = context.view(forKey: .from), let to = context.view(forKey: .to),
              let target = context.viewController(forKey: .to) else {
            context.completeTransition(false)
            onComplete()
            return
        }
        let container = context.containerView
        let page = isOpening ? to : from
        if isOpening { container.addSubview(to) }
        else { container.insertSubview(to, belowSubview: from) }
        to.frame = context.finalFrame(for: target)
        let fullFrame = page.frame
        let cover = source()
        let sourceAlpha = cover?.alpha ?? 1
        let sourceRect = cover.map { $0.convert($0.bounds, to: container) }
        let compact: CGAffineTransform
        if let rect = sourceRect, !rect.isEmpty, fullFrame.width > 0, fullFrame.height > 0 {
            let scale = min(rect.width / fullFrame.width, rect.height / fullFrame.height)
            compact = CGAffineTransform(translationX: rect.midX - fullFrame.midX, y: rect.midY - fullFrame.midY)
                .scaledBy(x: scale, y: scale)
        } else {
            compact = CGAffineTransform(translationX: fullFrame.width, y: 0)
        }
        let coverSnapshot = cover?.snapshotView(afterScreenUpdates: false)
        if let snapshot = coverSnapshot, let rect = sourceRect {
            snapshot.frame = isOpening ? rect : fullFrame
            snapshot.alpha = isOpening ? 1 : 0
            container.addSubview(snapshot)
        }
        cover?.alpha = 0
        page.transform = isOpening ? compact : .identity
        page.alpha = isOpening && coverSnapshot != nil ? 0 : 1
        UIView.animate(withDuration: transitionDuration(using: context), delay: 0,
                       options: [.curveEaseInOut, .beginFromCurrentState]) {
            page.transform = self.isOpening ? .identity : compact
            page.alpha = self.isOpening || coverSnapshot == nil ? 1 : 0
            coverSnapshot?.frame = self.isOpening ? fullFrame : (sourceRect ?? fullFrame)
            coverSnapshot?.alpha = self.isOpening ? 0 : 1
        } completion: { _ in
            let succeeded = !context.transitionWasCancelled
            page.transform = .identity
            page.alpha = 1
            cover?.alpha = sourceAlpha
            coverSnapshot?.removeFromSuperview()
            if self.isOpening && !succeeded { to.removeFromSuperview() }
            context.completeTransition(succeeded)
            self.onComplete()
        }
    }
}
