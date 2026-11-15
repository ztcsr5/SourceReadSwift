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
            interaction?.update(ReaderTransitionPolicy.dismissalProgress(translation: translation.x, width: width))
        case .ended:
            guard let driver = interaction else { return }
            let finish = translation.x > 0 && abs(translation.x) > abs(translation.y)
                && ReaderTransitionPolicy.shouldDismiss(translation: translation.x, velocity: velocity.x, width: width)
            if style == .parallax && !reducesMotion() {
                let progress = ReaderTransitionPolicy.dismissalProgress(translation: translation.x, width: width)
                driver.update(progress)
                driver.completionSpeed = ReaderSlideMotion.completionSpeed(
                    progress: progress, velocity: velocity.x, width: width, isFinishing: finish)
            } else {
                driver.completionSpeed = finish ? max(1.35, min(abs(velocity.x) / width, 2.8)) : 1.25
            }
            if finish {
                driver.finish()
            } else {
                driver.cancel()
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

@MainActor
private final class ReaderCompatibilityAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let isOpening: Bool
    let source: () -> UIView?
    let reducesMotion: Bool
    let style: ReaderNavigationStyle
    let onComplete: (Bool) -> Void
    private var activeAnimator: UIViewPropertyAnimator?

    init(isOpening: Bool, source: @escaping () -> UIView?, reducesMotion: Bool,
         style: ReaderNavigationStyle, onComplete: @escaping (Bool) -> Void) {
        self.isOpening = isOpening
        self.source = source
        self.reducesMotion = reducesMotion
        self.style = style
        self.onComplete = onComplete
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        reducesMotion ? 0.16 : (style == .parallax ? ReaderSlideMotion.layeredDuration : 0.24)
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        interruptibleAnimator(using: context).startAnimation()
    }

    func interruptibleAnimator(using context: UIViewControllerContextTransitioning) -> UIViewImplicitlyAnimating {
        if let activeAnimator { return activeAnimator }
        let duration = transitionDuration(using: context)
        let animator = context.isInteractive
            ? UIViewPropertyAnimator(duration: duration, curve: .linear)
            : UIViewPropertyAnimator(duration: duration,
                controlPoint1: CGPoint(x: 0.22, y: 0.82), controlPoint2: CGPoint(x: 0.28, y: 1))
        animator.isInterruptible = true
        animator.scrubsLinearly = true
        activeAnimator = animator

        let toView = context.view(forKey: .to) ?? (isOpening ? context.viewController(forKey: .to)?.view : nil)
        let fromView = context.view(forKey: .from) ?? (!isOpening ? context.viewController(forKey: .from)?.view : nil)
        guard let page = isOpening ? toView : fromView else {
            animator.addCompletion { [weak self] _ in
                self?.activeAnimator = nil
                context.completeTransition(false)
                self?.onComplete(false)
            }
            return animator
        }

        let container = context.containerView
        let insertsBackPlane = !isOpening && toView?.superview == nil
        if isOpening {
            if page.superview !== container { container.addSubview(page) }
            if let target = context.viewController(forKey: .to) {
                page.frame = context.finalFrame(for: target)
            }
        } else if let to = toView, page.superview === container {
            if insertsBackPlane { container.insertSubview(to, belowSubview: page) }
            if let target = context.viewController(forKey: .to) {
                to.frame = context.finalFrame(for: target)
            }
        }
        let underView = isOpening ? fromView : toView
        let originalTransform = page.transform
        let backgroundTransform = underView?.transform ?? .identity
        let visibleAlpha = page.alpha
        let decoration: [UIView]
        if reducesMotion || style == .fade || page.superview !== container {
            if isOpening { page.alpha = 0 }
            animator.addAnimations { [isOpening] in page.alpha = isOpening ? visibleAlpha : 0 }
            decoration = []
        } else {
            _ = source()
            decoration = animateSlide(page: page, underView: underView, in: container, animator: animator)
        }
        animator.addCompletion { [weak self, isOpening, onComplete] _ in
            let succeeded = !context.transitionWasCancelled
            page.transform = originalTransform
            page.alpha = visibleAlpha
            underView?.transform = backgroundTransform
            decoration.forEach { $0.removeFromSuperview() }
            if !succeeded {
                if isOpening { page.removeFromSuperview() }
                else if insertsBackPlane { toView?.removeFromSuperview() }
            }
            self?.activeAnimator = nil
            context.completeTransition(succeeded)
            onComplete(!isOpening && !succeeded)
        }
        return animator
    }

    private func animateSlide(page: UIView, underView: UIView?, in container: UIView, animator: UIViewPropertyAnimator) -> [UIView] {
        let direction: CGFloat = container.effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1
        let width = max(page.bounds.width, 1)
        let travel = CGAffineTransform(translationX: direction * width, y: 0)
        let backTravel = style == .parallax ? ReaderSlideMotion.backPlaneTravel(width: width) : width * 0.22
        let front = page.transform
        let back = underView?.transform ?? .identity
        let frontDisplaced = front.concatenating(travel)
        let backDisplaced = back.concatenating(CGAffineTransform(translationX: -direction * backTravel, y: 0))

        let veil = UIView(frame: container.bounds)
        veil.backgroundColor = UIColor.black.withAlphaComponent(style == .parallax ? 0.085 : 0.10)
        veil.isUserInteractionEnabled = false
        veil.alpha = isOpening ? 0 : 1
        container.insertSubview(veil, belowSubview: page)
        let edge = makeLeadingEdge(of: page.frame, rightToLeft: direction < 0)
        container.insertSubview(edge, belowSubview: page)

        // Only ordinary layer geometry and alpha change. No page snapshot,
        // large shadow pass, scaling or content re-layout while scrubbing.
        page.transform = isOpening ? frontDisplaced : front
        underView?.transform = isOpening ? back : backDisplaced
        edge.transform = isOpening ? travel : .identity
        animator.addAnimations { [isOpening] in
            page.transform = isOpening ? front : frontDisplaced
            underView?.transform = isOpening ? backDisplaced : back
            edge.transform = isOpening ? .identity : travel
            veil.alpha = isOpening ? 1 : 0
        }
        return [veil, edge]
    }

    private func makeLeadingEdge(of frame: CGRect, rightToLeft: Bool) -> UIView {
        let width: CGFloat = 16
        let edge = UIView(frame: CGRect(x: rightToLeft ? frame.maxX : frame.minX - width,
            y: frame.minY, width: width, height: frame.height))
        edge.isUserInteractionEnabled = false
        let gradient = CAGradientLayer()
        gradient.frame = edge.bounds
        let reach = UIColor.black.withAlphaComponent(0.19).cgColor
        gradient.colors = rightToLeft ? [reach, UIColor.clear.cgColor] : [UIColor.clear.cgColor, reach]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        edge.layer.addSublayer(gradient)
        return edge
    }
}
