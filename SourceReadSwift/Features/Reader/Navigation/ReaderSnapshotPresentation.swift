import UIKit

/// Owns a reader window in the existing scene, leaving the home/detail hierarchy mounted beneath it.
@MainActor
final class ReaderSnapshotPresentation: NSObject, UIGestureRecognizerDelegate {
    enum Phase { case opening, reading, returning, closed }
    private(set) var phase = Phase.opening
    private let reader: NativeReaderHostingController
    private weak var sourceWindow: UIWindow?
    private weak var previousKeyWindow: UIWindow?
    private let resolveSource: () -> UIView?
    private let onClosed: () -> Void
    private let interactiveReturn: Bool
    private var window: UIWindow?
    private let host = ReaderSnapshotHostController()
    private var animator: UIViewPropertyAnimator?
    private var flight: ReaderSnapshotFlightView?
    private var hasTriggeredEdgeReturn = false
    private lazy var edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(trackEdge(_:)))

    init(reader: NativeReaderHostingController, sourceWindow: UIWindow,
         configuration: Configuration, onClosed: @escaping () -> Void) {
        self.reader = reader
        self.sourceWindow = sourceWindow
        self.resolveSource = configuration.resolveSource
        self.interactiveReturn = configuration.interactiveReturn
        self.onClosed = onClosed
    }

    struct Configuration {
        let interactiveReturn: Bool
        let resolveSource: () -> UIView?
    }

    /// Returns false before changing any presentation state when no application scene is available.
    func present() -> Bool {
        guard let sourceWindow, let scene = sourceWindow.windowScene else { return false }
        previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let overlay = UIWindow(windowScene: scene)
        overlay.frame = sourceWindow.frame
        overlay.windowLevel = UIWindow.Level(rawValue: sourceWindow.windowLevel.rawValue + 1)
        overlay.backgroundColor = .clear
        overlay.overrideUserInterfaceStyle = sourceWindow.overrideUserInterfaceStyle
        overlay.rootViewController = host
        window = overlay
        host.onResize = { [weak self] in self?.settleBeforeResize() }
        host.loadViewIfNeeded()
        host.view.frame = overlay.bounds
        host.mount(reader)
        reader.view.isHidden = true
        edge.edges = .left
        edge.delegate = self
        edge.name = ReaderCompatibilityTransition.edgeGestureName
        host.view.addGestureRecognizer(edge)
        let source = sourceGeometry(in: overlay)
        let carrier = ReaderSnapshotFlightView(frame: overlay.bounds, paper: reader.view.backgroundColor ?? .systemBackground,
            page: nil, cover: source?.cover)
        flight = carrier
        host.view.addSubview(carrier)
        carrier.transform = UIAccessibility.isReduceMotionEnabled ? .identity
            : source.map { ReaderSnapshotFlightView.transform(from: overlay.bounds, to: $0.rect) }
                ?? CGAffineTransform(scaleX: 0.97, y: 0.97)
        carrier.alpha = source == nil ? 0 : 1
        overlay.makeKeyAndVisible()
        reader.view.isUserInteractionEnabled = false
        reader.session.recordBridgeEvent("snapshot:opening")
        let opening = UIViewPropertyAnimator(duration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.42,
            dampingRatio: 0.9) {
            carrier.transform = .identity
            carrier.alpha = 1
            carrier.coverAlpha = 0
        }
        animator = opening
        opening.addCompletion { [weak self] position in
            guard let self, self.phase == .opening else { return }
            self.animator = nil
            if position == .start { self.tearDown(); return }
            // The fixed-size reader has already mounted behind this plain paper surface.
            // Only the carrier fades; the live WebView never scales or changes its viewport.
            self.reader.view.isHidden = false
            UIView.animate(withDuration: 0.12, animations: { carrier.alpha = 0 }) { [weak self] _ in
                guard let self, self.phase == .opening else { return }
                carrier.removeFromSuperview()
                self.flight = nil
                self.phase = .reading
                self.reader.view.isUserInteractionEnabled = true
                self.reader.session.didAppear()
                self.reader.session.recordBridgeEvent("snapshot:opened")
                UIAccessibility.post(notification: .screenChanged, argument: self.reader.view)
            }
        }
        opening.startAnimation()
        return true
    }

    /// A button return uses the same snapshot and completion boundary as an edge sweep.
    func close() {
        if phase == .opening {
            if let animator {
                if animator.isRunning { animator.pauseAnimation() }
                animator.isReversed = true
                animator.continueAnimation(withTimingParameters: nil, durationFactor: 1)
            } else { tearDown() }
            return
        }
        guard phase == .reading else { return }
        beginReturn(interactive: false)
    }

    func updateAppearance(_ style: UIUserInterfaceStyle) { window?.overrideUserInterfaceStyle = style }

    func beginReturn(interactive: Bool) {
        guard phase == .reading, let window else { return }
        let source = sourceGeometry(in: window)
        let page = reader.view.snapshotView(afterScreenUpdates: false)
        let carrier = ReaderSnapshotFlightView(frame: host.view.bounds, paper: reader.view.backgroundColor ?? .systemBackground,
            page: page, cover: source?.cover)
        carrier.coverAlpha = 0
        flight = carrier
        host.view.addSubview(carrier)
        reader.view.isHidden = true
        reader.view.isUserInteractionEnabled = false
        phase = .returning
        reader.session.willLeave()
        reader.session.recordBridgeEvent(page == nil ? "snapshot:paper-fallback" : "snapshot:captured")
        let closing = UIViewPropertyAnimator(duration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.4,
            dampingRatio: 0.92) {
            carrier.transform = UIAccessibility.isReduceMotionEnabled ? .identity
                : source.map { ReaderSnapshotFlightView.transform(from: self.host.view.bounds, to: $0.rect) }
                    ?? CGAffineTransform(scaleX: 0.97, y: 0.97)
            carrier.coverAlpha = source == nil ? 0 : 1
            carrier.pageAlpha = 0
            if source == nil || UIAccessibility.isReduceMotionEnabled { carrier.alpha = 0 }
        }
        animator = closing
        closing.addCompletion { [weak self] position in
            guard let self, self.phase == .returning else { return }
            self.animator = nil
            if position == .start { self.cancelReturn() }
            else { self.tearDown() }
        }
        closing.startAnimation()
        if interactive { closing.pauseAnimation() }
    }

    func updateReturn(progress: CGFloat) {
        guard phase == .returning, let animator else { return }
        animator.fractionComplete = min(max(progress, 0), 1)
    }

    func endReturn(completes: Bool) {
        guard phase == .returning, let animator else { return }
        if animator.isRunning { animator.pauseAnimation() }
        animator.isReversed = !completes
        animator.continueAnimation(withTimingParameters: nil, durationFactor: 1)
    }

    private func cancelReturn() {
        flight?.removeFromSuperview()
        flight = nil
        reader.view.isHidden = false
        reader.view.isUserInteractionEnabled = true
        phase = .reading
        reader.session.didAppear()
        reader.session.recordBridgeEvent("snapshot:cancelled")
    }

    private func settleBeforeResize() {
        guard phase == .opening || phase == .returning else { return }
        animator?.stopAnimation(true)
        animator = nil
        cancelReturn()
    }

    private func tearDown() {
        guard phase != .closed else { return }
        phase = .closed
        animator?.stopAnimation(true)
        animator = nil
        flight?.removeFromSuperview()
        flight = nil
        reader.view.isHidden = false
        host.unmount(reader)
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        if let previousKeyWindow, !previousKeyWindow.isHidden { previousKeyWindow.makeKey() }
        else { sourceWindow?.makeKey() }
        reader.session.recordBridgeEvent("snapshot:closed")
        onClosed()
        UIAccessibility.post(notification: .screenChanged, argument: sourceWindow?.rootViewController?.view)
    }

    private func sourceGeometry(in target: UIWindow) -> (rect: CGRect, cover: UIView?)? {
        guard !UIAccessibility.isReduceMotionEnabled, let anchor = resolveSource(),
              let sourceWindow, anchor.window === sourceWindow else { return nil }
        let rect = anchor.convert(anchor.bounds, to: target)
        guard rect.width > 1, rect.height > 1,
              target.bounds.intersection(rect).width * target.bounds.intersection(rect).height >= rect.width * rect.height * 0.9
        else { return nil }
        // The registered anchor is transparent. Capture its hosting surface without hiding or mutating it.
        let cover = (anchor.superview ?? anchor).snapshotView(afterScreenUpdates: false)
        return (rect, cover)
    }

    @objc private func trackEdge(_ gesture: UIScreenEdgePanGestureRecognizer) {
        let translation = gesture.translation(in: host.view)
        let velocity = gesture.velocity(in: host.view)
        if gesture.state == .began { hasTriggeredEdgeReturn = false }
        if phase == .opening {
            if !hasTriggeredEdgeReturn, ReaderSnapshotGesturePolicy.triggers(translation: translation, velocity: velocity) {
                hasTriggeredEdgeReturn = true
                close()
            }
            return
        }
        if interactiveReturn {
            switch gesture.state {
            case .began: beginReturn(interactive: true)
            case .changed: updateReturn(progress: translation.x / max(host.view.bounds.width, 1))
            case .ended:
                endReturn(completes: translation.x + velocity.x * 0.15 > host.view.bounds.width * 0.32)
            case .cancelled, .failed: endReturn(completes: false)
            default: break
            }
        } else if !hasTriggeredEdgeReturn,
                  gesture.state == .began || gesture.state == .changed || gesture.state == .ended,
                  ReaderSnapshotGesturePolicy.triggers(translation: translation, velocity: velocity) {
            hasTriggeredEdgeReturn = true
            close()
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard phase == .reading || phase == .opening,
              reader.session.allowsReturn, reader.presentedViewController == nil else { return false }
        let velocity = edge.velocity(in: host.view)
        return velocity.x > abs(velocity.y)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let x = touch.location(in: host.view).x
        return x >= 0 && x <= 24
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        otherGestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer !== edge
    }
}

enum ReaderSnapshotGesturePolicy {
    static func triggers(translation: CGPoint, velocity: CGPoint) -> Bool {
        guard translation.x > abs(translation.y) else { return false }
        return translation.x >= 28 || (translation.x >= 8 && velocity.x >= 650 && velocity.x > abs(velocity.y))
    }
}

private final class ReaderSnapshotHostController: UIViewController {
    var onResize: () -> Void = {}
    private var previousSize = CGSize.zero
    override var childForStatusBarHidden: UIViewController? { children.first }
    override var childForStatusBarStyle: UIViewController? { children.first }
    override var childForHomeIndicatorAutoHidden: UIViewController? { children.first }
    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        if previousSize != .zero && previousSize != size { onResize() }
        previousSize = size
    }
    func mount(_ reader: UIViewController) {
        addChild(reader)
        reader.view.frame = view.bounds
        reader.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(reader.view)
        reader.didMove(toParent: self)
    }
    func unmount(_ reader: UIViewController) {
        reader.willMove(toParent: nil)
        reader.view.removeFromSuperview()
        reader.removeFromParent()
    }
}
