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
        reducesMotion ? 0.16 : style.transitionDuration
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
                controlPoint1: CGPoint(x: 0.28, y: 0.92), controlPoint2: CGPoint(x: 0.36, y: 1.0))
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
        let originalLayerTransform = page.layer.transform
        let originalAnchorPoint = page.layer.anchorPoint
        let originalPosition = page.layer.position
        let originalCornerRadius = page.layer.cornerRadius
        let backgroundTransform = underView?.transform ?? .identity
        let backgroundCornerRadius = underView?.layer.cornerRadius ?? 0
        let visibleAlpha = page.alpha
        let decoration: [UIView]
        if reducesMotion || style == .fade || page.superview !== container {
            if isOpening { page.alpha = 0 }
            animator.addAnimations { [isOpening] in page.alpha = isOpening ? visibleAlpha : 0 }
            decoration = []
        } else {
            _ = source()
            switch style {
            case .depthZoom:
                decoration = animateDepthZoom(page: page, underView: underView, in: container, animator: animator)
            case .magneticCard:
                decoration = animateMagneticCard(page: page, underView: underView, in: container, animator: animator)
            case .fanUnfold:
                decoration = animateFanUnfold(page: page, underView: underView, in: container, animator: animator)
            case .bookFlip:
                decoration = animateBookFlip(page: page, underView: underView, in: container, animator: animator)
            case .sheetRise:
                decoration = animateSheetRise(page: page, underView: underView, in: container, animator: animator)
            default:
                decoration = animateSlide(page: page, underView: underView, in: container, animator: animator)
            }
        }
        animator.addCompletion { [weak self, isOpening, onComplete] _ in
            let succeeded = !context.transitionWasCancelled
            page.layer.anchorPoint = originalAnchorPoint
            page.layer.position = originalPosition
            page.layer.transform = originalLayerTransform
            page.transform = originalTransform
            page.layer.cornerRadius = originalCornerRadius
            page.alpha = visibleAlpha
            underView?.transform = backgroundTransform
            underView?.layer.cornerRadius = backgroundCornerRadius
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

    private func animateMagneticCard(page: UIView, underView: UIView?, in container: UIView, animator: UIViewPropertyAnimator) -> [UIView] {
        let veil = UIView(frame: container.bounds)
        veil.backgroundColor = UIColor.black.withAlphaComponent(0.24)
        veil.isUserInteractionEnabled = false
        veil.alpha = isOpening ? 0 : 1
        container.insertSubview(veil, belowSubview: page)

        let front = page.transform
        let back = underView?.transform ?? .identity
        let frontCompact = front
            .concatenating(CGAffineTransform(scaleX: 0.90, y: 0.90))
            .concatenating(CGAffineTransform(translationX: 0, y: 54))
        let backReceded = back.concatenating(CGAffineTransform(scaleX: 0.935, y: 0.935))

        page.layer.cornerCurve = .continuous
        page.layer.cornerRadius = isOpening ? 38 : 0
        page.transform = isOpening ? frontCompact : front
        page.alpha = isOpening ? 0.1 : 1
        underView?.layer.cornerCurve = .continuous
        underView?.layer.cornerRadius = isOpening ? 0 : 24
        underView?.transform = isOpening ? back : backReceded

        animator.addAnimations { [isOpening] in
            page.transform = isOpening ? front : frontCompact
            page.layer.cornerRadius = isOpening ? 0 : 38
            page.alpha = isOpening ? 1 : 0.08
            underView?.transform = isOpening ? backReceded : back
            underView?.layer.cornerRadius = isOpening ? 24 : 0
            veil.alpha = isOpening ? 1 : 0
        }
        return [veil]
    }

    private func animateFanUnfold(page: UIView, underView: UIView?, in container: UIView, animator: UIViewPropertyAnimator) -> [UIView] {
        let veil = UIView(frame: container.bounds)
        veil.backgroundColor = UIColor.black.withAlphaComponent(0.20)
        veil.isUserInteractionEnabled = false
        veil.alpha = isOpening ? 0 : 1
        container.insertSubview(veil, belowSubview: page)

        let isRTL = container.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let sign: CGFloat = isRTL ? -1 : 1
        let front = page.transform
        let back = underView?.transform ?? .identity
        let frontFan = front
            .concatenating(CGAffineTransform(scaleX: 0.88, y: 0.88))
            .concatenating(CGAffineTransform(rotationAngle: sign * 0.115))
            .concatenating(CGAffineTransform(translationX: sign * 42, y: 26))
        let backReceded = back
            .concatenating(CGAffineTransform(scaleX: 0.95, y: 0.95))
            .concatenating(CGAffineTransform(translationX: -sign * 18, y: 0))

        page.layer.cornerCurve = .continuous
        page.layer.cornerRadius = isOpening ? 30 : 0
        page.transform = isOpening ? frontFan : front
        page.alpha = isOpening ? 0.05 : 1
        underView?.transform = isOpening ? back : backReceded

        animator.addAnimations { [isOpening] in
            page.transform = isOpening ? front : frontFan
            page.layer.cornerRadius = isOpening ? 0 : 30
            page.alpha = isOpening ? 1 : 0.05
            underView?.transform = isOpening ? backReceded : back
            veil.alpha = isOpening ? 1 : 0
        }
        return [veil]
    }

    private func animateDepthZoom(page: UIView, underView: UIView?, in container: UIView, animator: UIViewPropertyAnimator) -> [UIView] {
        let veil = UIView(frame: container.bounds)
        veil.backgroundColor = UIColor.black.withAlphaComponent(0.20)
        veil.isUserInteractionEnabled = false
        veil.alpha = isOpening ? 0 : 1
        container.insertSubview(veil, belowSubview: page)

        let front = page.transform
        let back = underView?.transform ?? .identity
        let frontCompact = front.concatenating(CGAffineTransform(scaleX: 0.90, y: 0.90))
        let backReceded = back.concatenating(CGAffineTransform(scaleX: 0.94, y: 0.94))

        page.layer.cornerCurve = .continuous
        page.layer.cornerRadius = isOpening ? 28 : 0
        page.transform = isOpening ? frontCompact : front
        page.alpha = isOpening ? 0 : 1
        underView?.transform = isOpening ? back : backReceded

        animator.addAnimations { [isOpening] in
            page.transform = isOpening ? front : frontCompact
            page.layer.cornerRadius = isOpening ? 0 : 28
            page.alpha = isOpening ? 1 : 0
            underView?.transform = isOpening ? backReceded : back
            veil.alpha = isOpening ? 1 : 0
        }
        return [veil]
    }

    private func animateBookFlip(page: UIView, underView: UIView?, in container: UIView, animator: UIViewPropertyAnimator) -> [UIView] {
        let veil = UIView(frame: container.bounds)
        veil.backgroundColor = UIColor.black.withAlphaComponent(0.24)
        veil.isUserInteractionEnabled = false
        veil.alpha = isOpening ? 0 : 1
        container.insertSubview(veil, belowSubview: page)

        let width = max(page.bounds.width, 1)
        let isRTL = container.effectiveUserInterfaceLayoutDirection == .rightToLeft
        page.layer.anchorPoint = CGPoint(x: isRTL ? 1.0 : 0.0, y: 0.5)
        page.layer.position = CGPoint(x: isRTL ? container.bounds.maxX : container.bounds.minX, y: container.bounds.midY)

        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / max(width * 2.2, 1)
        let closedAngle: CGFloat = (isRTL ? 1 : -1) * (.pi * 0.48)
        let closedTransform = CATransform3DRotate(perspective, closedAngle, 0, 1, 0)
        let back = underView?.transform ?? .identity
        let backReceded = back.concatenating(CGAffineTransform(scaleX: 0.95, y: 0.95))

        page.layer.cornerCurve = .continuous
        page.layer.cornerRadius = isOpening ? 16 : 0
        page.layer.transform = isOpening ? closedTransform : CATransform3DIdentity
        page.alpha = isOpening ? 0.15 : 1
        underView?.transform = isOpening ? back : backReceded

        animator.addAnimations { [isOpening] in
            page.layer.transform = isOpening ? CATransform3DIdentity : closedTransform
            page.layer.cornerRadius = isOpening ? 0 : 16
            page.alpha = isOpening ? 1 : 0.15
            underView?.transform = isOpening ? backReceded : back
            veil.alpha = isOpening ? 1 : 0
        }
        return [veil]
    }

    private func animateSheetRise(page: UIView, underView: UIView?, in container: UIView, animator: UIViewPropertyAnimator) -> [UIView] {
        let veil = UIView(frame: container.bounds)
        veil.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        veil.isUserInteractionEnabled = false
        veil.alpha = isOpening ? 0 : 1
        container.insertSubview(veil, belowSubview: page)

        let height = max(container.bounds.height, 1)
        let front = page.transform
        let back = underView?.transform ?? .identity
        let frontDown = front.concatenating(CGAffineTransform(translationX: 0, y: height))
        let backSunk = back.concatenating(CGAffineTransform(scaleX: 0.93, y: 0.93))

        page.layer.cornerCurve = .continuous
        page.layer.cornerRadius = isOpening ? 34 : 0
        page.transform = isOpening ? frontDown : front
        underView?.layer.cornerCurve = .continuous
        underView?.layer.cornerRadius = isOpening ? 0 : 20
        underView?.transform = isOpening ? back : backSunk

        animator.addAnimations { [isOpening] in
            page.transform = isOpening ? front : frontDown
            page.layer.cornerRadius = isOpening ? 0 : 34
            underView?.transform = isOpening ? backSunk : back
            underView?.layer.cornerRadius = isOpening ? 20 : 0
            veil.alpha = isOpening ? 1 : 0
        }
        return [veil]
    }

    private func animateSlide(page: UIView, underView: UIView?, in container: UIView, animator: UIViewPropertyAnimator) -> [UIView] {
        let direction: CGFloat = container.effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1
        let width = max(page.bounds.width, 1)
        let travel = CGAffineTransform(translationX: direction * width, y: 0)
        let backTravel = style == .parallax ? ReaderSlideMotion.backPlaneTravel(width: width) : width * 0.22
        let front = page.transform
        let back = underView?.transform ?? .identity
        let frontDisplaced = front.concatenating(travel)
        let backScale: CGFloat = style == .parallax ? 0.968 : 1.0
        let backDisplaced = back
            .concatenating(CGAffineTransform(scaleX: backScale, y: backScale))
            .concatenating(CGAffineTransform(translationX: -direction * backTravel, y: 0))

        let veil = UIView(frame: container.bounds)
        veil.backgroundColor = UIColor.black.withAlphaComponent(style == .parallax ? 0.11 : 0.10)
        veil.isUserInteractionEnabled = false
        veil.alpha = isOpening ? 0 : 1
        container.insertSubview(veil, belowSubview: page)
        let edge = makeLeadingEdge(of: page.frame, rightToLeft: direction < 0)
        container.insertSubview(edge, belowSubview: page)

        page.layer.cornerCurve = .continuous
        page.layer.cornerRadius = isOpening ? 24 : 8
        page.transform = isOpening ? frontDisplaced : front
        underView?.transform = isOpening ? back : backDisplaced
        edge.transform = isOpening ? travel : .identity
        animator.addAnimations { [isOpening] in
            page.transform = isOpening ? front : frontDisplaced
            page.layer.cornerRadius = isOpening ? 0 : 24
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
