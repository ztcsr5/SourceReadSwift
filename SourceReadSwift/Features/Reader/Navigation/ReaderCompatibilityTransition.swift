import UIKit

/// iOS 16/17 compatibility uses UIKit's transition context and cancellation, never a timed unmount.
@MainActor
final class ReaderCompatibilityTransition: NSObject, UIViewControllerTransitioningDelegate, UIGestureRecognizerDelegate {
    nonisolated static let edgeGestureName = "reader.compatibilityReturn"
    let session: ReaderNavigationSession
    let source: () -> UIView?
    private let reducesMotion: @MainActor () -> Bool
    private let style: ReaderNavigationStyle
    private(set) var interaction: UIPercentDrivenInteractiveTransition?
    private var beginReturn: () -> Void = {}
    private var canBeginReturn: () -> Bool = { true }
    private weak var gestureHost: UIView?
    private lazy var edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(track(_:)))

    init(session: ReaderNavigationSession, source: @escaping () -> UIView?, style: ReaderNavigationStyle = .system,
         reducesMotion: @escaping @MainActor () -> Bool = { UIAccessibility.isReduceMotionEnabled }) {
        self.session = session
        self.source = source
        self.style = style
        self.reducesMotion = reducesMotion
        super.init()
        edge.name = Self.edgeGestureName
        edge.edges = .left
        edge.delegate = self
        edge.maximumNumberOfTouches = 1
    }

    func attach(to view: UIView, canBeginReturn: @escaping () -> Bool = { true }, beginReturn: @escaping () -> Void) {
        detach()
        self.beginReturn = beginReturn
        self.canBeginReturn = canBeginReturn
        gestureHost = view
        edge.edges = view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
        view.addGestureRecognizer(edge)
    }

    func detach() { edge.view?.removeGestureRecognizer(edge) }
    func didSettle(cancelledReturn: Bool = false) {
        interaction = nil
        if cancelledReturn, session.phase == .returning {
            session.didAppear()
        }
    }

    /// UIKit needs an animated transaction to hand control to the percent driver.
    var shouldAnimateReturn: Bool { interaction != nil || !reducesMotion() }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let location = gestureRecognizer.location(in: gestureHost)
        let accepted = session.phase == .reading && session.allowsReturn && interaction == nil && canBeginReturn()
        session.recordZoomDecision(location: location, willBegin: false, accepted: accepted)
        return accepted
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Content pans wait for the edge recognizer, preserving ordinary scrolling away from the edge.
        guard gestureRecognizer === edge, otherGestureRecognizer !== edge,
              otherGestureRecognizer is UIPanGestureRecognizer, let host = gestureHost,
              let other = otherGestureRecognizer.view else { return false }
        return other.isDescendant(of: host)
    }

    @objc private func track(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard let host = gestureHost else { return }
        let direction: CGFloat = edge.edges == .right ? -1 : 1
        let translation = gesture.translation(in: host), velocity = gesture.velocity(in: host)
        updateGesture(state: gesture.state, translation: CGPoint(x: translation.x * direction, y: translation.y),
                      velocity: CGPoint(x: velocity.x * direction, y: velocity.y), width: host.bounds.width)
    }

    /// Routes recognized edge samples through UIKit's real interactive transition driver.
    func updateGesture(state: UIGestureRecognizer.State, translation: CGPoint, velocity: CGPoint, width: CGFloat) {
        let width = max(width, 1)
        switch state {
        case .began:
            session.recordZoomDecision(location: translation, willBegin: true, accepted: true)
            if style.providesAnimator { session.recordInteractivePopBegin() }
            let driver = UIPercentDrivenInteractiveTransition()
            driver.completionCurve = .easeOut
            interaction = driver
            beginReturn()
        case .changed:
            interaction?.update(min(max(translation.x / width, 0), 1))
        case .ended:
            let finish = translation.x > 0 && abs(translation.x) > abs(translation.y)
                && ReaderTransitionPolicy.shouldDismiss(translation: translation.x, velocity: velocity.x, width: width)
            if finish {
                interaction?.completionSpeed = max(1.35, min(abs(velocity.x) / width, 2.8))
                interaction?.finish()
            } else {
                interaction?.completionSpeed = 1.25
                interaction?.cancel()
            }
        case .cancelled, .failed:
            interaction?.completionSpeed = 1.25
            interaction?.cancel()
        default: break
        }
    }

    func animator(isOpening: Bool) -> UIViewControllerAnimatedTransitioning {
        let wasInteractive = interaction != nil
        return ReaderCompatibilityAnimator(isOpening: isOpening, source: source,
                                    reducesMotion: reducesMotion(), style: style) { [weak self] cancelledReturn in
            if !isOpening, let self, self.style.providesAnimator, wasInteractive {
                self.session.recordBridgeEvent(cancelledReturn ? "custom-pop:cancelled" : "custom-pop:completed")
            }
            self?.didSettle(cancelledReturn: cancelledReturn)
        }
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
    let reducesMotion: Bool
    let style: ReaderNavigationStyle
    let onComplete: (Bool) -> Void

    init(isOpening: Bool, source: @escaping () -> UIView?, reducesMotion: Bool,
         style: ReaderNavigationStyle, onComplete: @escaping (Bool) -> Void) {
        self.isOpening = isOpening
        self.source = source
        self.reducesMotion = reducesMotion
        self.style = style
        self.onComplete = onComplete
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        reducesMotion ? 0.16 : (style == .paperFold ? 0.30 : 0.24)
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        let toView = context.view(forKey: .to) ?? (isOpening ? context.viewController(forKey: .to)?.view : nil)
        let fromView = context.view(forKey: .from) ?? (!isOpening ? context.viewController(forKey: .from)?.view : nil)
        guard let page = isOpening ? toView : fromView else {
            context.completeTransition(false)
            onComplete(false)
            return
        }
        let container = context.containerView
        if isOpening {
            if page.superview !== container { container.addSubview(page) }
            if let target = context.viewController(forKey: .to) {
                page.frame = context.finalFrame(for: target)
            }
        } else if let to = toView {
            if to.superview == nil { container.insertSubview(to, belowSubview: page) }
            if let target = context.viewController(forKey: .to) {
                to.frame = context.finalFrame(for: target)
            }
        }
        if reducesMotion || style == .fade {
            animateFade(page: page, context: context)
            return
        }
        let fullFrame = page.frame
        _ = source()
        let underView = isOpening ? fromView : toView
        let direction: CGFloat = container.effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1
        let width = max(fullFrame.width, 1)
        let slideOffset = style == .paperFold
            ? CGAffineTransform(translationX: direction * width * 0.36, y: 24).scaledBy(x: 0.78, y: 0.78)
            : CGAffineTransform(translationX: direction * width, y: 0)
        let parallaxOffset = CGAffineTransform(translationX: -direction * width * 0.22, y: 0)

        let veil = UIView(frame: container.bounds)
        veil.backgroundColor = UIColor.black.withAlphaComponent(0.10)
        veil.isUserInteractionEnabled = false
        veil.alpha = isOpening ? 0 : 1
        container.insertSubview(veil, belowSubview: page)

        let previousShadowOpacity = page.layer.shadowOpacity
        let previousShadowRadius = page.layer.shadowRadius
        let previousShadowOffset = page.layer.shadowOffset
        let previousShadowPath = page.layer.shadowPath
        let previousShadowColor = page.layer.shadowColor
        page.layer.shadowPath = UIBezierPath(rect: page.bounds).cgPath
        page.layer.shadowColor = UIColor.black.cgColor
        page.layer.shadowOpacity = 0.16
        page.layer.shadowRadius = 16
        page.layer.shadowOffset = CGSize(width: -5, height: 0)

        page.transform = isOpening ? slideOffset : .identity
        page.alpha = isOpening && style == .paperFold ? 0 : 1
        underView?.transform = isOpening ? .identity : parallaxOffset

        let curveOption: UIView.AnimationOptions = context.isInteractive ? .curveLinear : .curveEaseOut
        UIView.animate(withDuration: transitionDuration(using: context), delay: 0,
                       options: [curveOption, .beginFromCurrentState]) {
            page.transform = self.isOpening ? .identity : slideOffset
            if self.style == .paperFold { page.alpha = self.isOpening ? 1 : 0 }
            underView?.transform = self.isOpening ? parallaxOffset : .identity
            veil.alpha = self.isOpening ? 1 : 0
        } completion: { _ in
            let succeeded = !context.transitionWasCancelled
            page.transform = .identity
            page.alpha = 1
            page.layer.shadowOpacity = previousShadowOpacity
            page.layer.shadowRadius = previousShadowRadius
            page.layer.shadowOffset = previousShadowOffset
            page.layer.shadowPath = previousShadowPath
            page.layer.shadowColor = previousShadowColor
            underView?.transform = .identity
            veil.removeFromSuperview()
            if self.isOpening && !succeeded { page.removeFromSuperview() }
            context.completeTransition(succeeded)
            self.onComplete(!self.isOpening && !succeeded)
        }
    }

    private func animateFade(page: UIView, context: UIViewControllerContextTransitioning) {
        let visibleAlpha = page.alpha
        if isOpening { page.alpha = 0 }
        let curveOption: UIView.AnimationOptions = context.isInteractive ? .curveLinear : .curveEaseInOut
        UIView.animate(withDuration: transitionDuration(using: context), delay: 0, options: [curveOption]) {
            page.alpha = self.isOpening ? visibleAlpha : 0
        } completion: { _ in
            let succeeded = !context.transitionWasCancelled
            page.alpha = visibleAlpha
            if self.isOpening && !succeeded { page.removeFromSuperview() }
            context.completeTransition(succeeded)
            self.onComplete(!self.isOpening && !succeeded)
        }
    }
}
