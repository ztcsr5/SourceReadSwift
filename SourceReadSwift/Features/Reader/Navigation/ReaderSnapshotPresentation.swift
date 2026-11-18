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
    private var returnCover: UIView?
    private var preparedReturnPage: UIView?
    private var preparedReturnRevision: Int?
    private var returnSnapshotTask: DispatchWorkItem?
    private var hasTriggeredEdgeReturn = false
    private var returnProgressAtGestureStart: CGFloat = 0
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
        reader.view.alpha = 0
        reader.session.onVisualStateChanged = { [weak self] in self?.scheduleReturnSnapshotPreparation() }
        edge.edges = .left
        edge.delegate = self
        edge.name = ReaderCompatibilityTransition.edgeGestureName
        host.view.addGestureRecognizer(edge)
        let source = sourceGeometry(in: overlay)
        let carrier = ReaderSnapshotFlightView(frame: overlay.bounds, paper: reader.view.backgroundColor ?? .systemBackground,
            page: nil, cover: source?.cover)
        returnCover = source?.cover
        flight = carrier
        host.view.addSubview(carrier)
        if !UIAccessibility.isReduceMotionEnabled, let source {
            carrier.move(to: source.rect, cornerRadius: source.cornerRadius)
        }
        overlay.makeKeyAndVisible()
        reader.view.isUserInteractionEnabled = false
        reader.session.recordBridgeEvent("snapshot:opening")
        let opening = UIViewPropertyAnimator(duration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.44,
            dampingRatio: 0.94) {
            carrier.move(to: overlay.bounds, cornerRadius: 0)
            carrier.coverAlpha = 0
        }
        // Cross-fade the real reader smoothly during the cover unfold so it never
        // reads as an empty card flash.
        opening.addAnimations({ [weak self] in
            self?.reader.view.alpha = 1
            carrier.alpha = 0
        }, delayFactor: 0.24)
        animator = opening
        opening.addCompletion { [weak self] position in
            guard let self, self.phase == .opening else { return }
            self.animator = nil
            if position == .start { self.tearDown(); return }
            carrier.removeFromSuperview()
            self.flight = nil
            self.phase = .reading
            self.reader.view.alpha = 1
            self.reader.view.isUserInteractionEnabled = true
            self.reader.session.didAppear()
            self.reader.session.recordBridgeEvent("snapshot:opened")
            self.scheduleReturnSnapshotPreparation()
            UIAccessibility.post(notification: .screenChanged, argument: self.reader.view)
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

    func updateAppearance(_ style: UIUserInterfaceStyle) {
        guard window?.overrideUserInterfaceStyle != style else { return }
        window?.overrideUserInterfaceStyle = style
        scheduleReturnSnapshotPreparation()
    }

    /// Used by the reader bridge and deterministic tests before a visual change.
    func invalidatePreparedReturnSnapshot() {
        returnSnapshotTask?.cancel()
        returnSnapshotTask = nil
        preparedReturnPage = nil
        preparedReturnRevision = nil
    }

    func beginReturn(interactive: Bool) {
        if phase == .returning, interactive, interactiveReturn, let animator {
            if animator.isRunning { animator.pauseAnimation() }
            animator.isReversed = false
            reader.session.recordBridgeEvent("snapshot:reclaimed")
            return
        }
        guard phase == .reading, let window else { return }
        let source = sourceGeometry(in: window, captureCover: false)
        // A missing or stale snapshot dissolves the real page at its original size.
        let page = hasFreshReturnSnapshot ? preparedReturnPage : nil
        invalidatePreparedReturnSnapshot()
        let carrier = page.map { page in
            ReaderSnapshotFlightView(frame: host.view.bounds, paper: reader.view.backgroundColor ?? .systemBackground,
                page: page, cover: source?.cover)
        }
        if let carrier {
            carrier.coverAlpha = 0
            host.view.addSubview(carrier)
        }
        flight = carrier
        reader.view.isHidden = carrier != nil
        reader.view.isUserInteractionEnabled = false
        phase = .returning
        reader.session.willLeave()
        reader.session.recordBridgeEvent(carrier == nil ? "snapshot:live-fade" : "snapshot:captured")
        let livePage = reader.viewIfLoaded
        let closing = UIViewPropertyAnimator(duration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.42,
            dampingRatio: 0.95) {
            guard let carrier else { livePage?.alpha = 0; return }
            if !UIAccessibility.isReduceMotionEnabled, let source {
                carrier.move(to: source.rect, cornerRadius: source.cornerRadius)
            }
            carrier.coverAlpha = source == nil ? 0 : 1
            carrier.pageAlpha = 0
            if source == nil || UIAccessibility.isReduceMotionEnabled { carrier.alpha = 0 }
        }
        animator = closing
        closing.scrubsLinearly = true
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

    func endReturn(completes: Bool, velocity: CGFloat = 0) {
        guard phase == .returning, let animator else { return }
        if animator.isRunning { animator.pauseAnimation() }
        let release = ReaderSnapshotGesturePolicy.releaseVelocity(progress: animator.fractionComplete,
            velocity: velocity, width: host.view.bounds.width, completes: completes)
        animator.isReversed = !completes
        let timing = UIAccessibility.isReduceMotionEnabled ? nil
            : UISpringTimingParameters(dampingRatio: 0.95, initialVelocity: release)
        animator.continueAnimation(withTimingParameters: timing, durationFactor: 1)
    }

    private func cancelReturn() {
        flight?.removeFromSuperview()
        flight = nil
        reader.view.isHidden = false
        reader.view.alpha = 1
        reader.view.isUserInteractionEnabled = true
        phase = .reading
        reader.session.didAppear()
        reader.session.recordBridgeEvent("snapshot:cancelled")
        scheduleReturnSnapshotPreparation()
    }

    var hasFreshReturnSnapshot: Bool {
        preparedReturnRevision == reader.session.renderRevision
            && preparedReturnPage?.bounds.size == reader.viewIfLoaded?.bounds.size
            && preparedReturnPage != nil
    }

    private func scheduleReturnSnapshotPreparation() {
        invalidatePreparedReturnSnapshot()
        guard phase == .reading, reader.session.isContentReady, !reader.session.isContentMoving,
              !UIAccessibility.isReduceMotionEnabled else { return }
        let preparation = DispatchWorkItem { [weak self] in
            guard let self, self.phase == .reading, self.reader.view.window != nil,
                  self.reader.presentedViewController == nil else { return }
            self.returnSnapshotTask = nil
            let capture = PerformanceSignpost.begin("reader.return.capture")
            defer { PerformanceSignpost.end("reader.return.capture", id: capture) }
            self.preparedReturnPage = self.reader.view.snapshotView(afterScreenUpdates: false)
            self.preparedReturnRevision = self.reader.session.renderRevision
        }
        returnSnapshotTask = preparation
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80), execute: preparation)
    }

    func settleBeforeResize() {
        if phase == .reading {
            scheduleReturnSnapshotPreparation()
            return
        }
        guard phase == .opening || phase == .returning else { return }
        let isClosingOpening = phase == .opening && animator?.isReversed == true
        animator?.stopAnimation(true)
        animator = nil
        if isClosingOpening {
            tearDown()
        } else if phase == .opening {
            // A rotation/scene resize can interrupt the opening carrier before
            // UIKit has delivered its completion. Reveal the mounted reader
            // instead of routing opening through return-cancel.
            flight?.removeFromSuperview()
            flight = nil
            reader.view.alpha = 1
            reader.view.isUserInteractionEnabled = true
            phase = .reading
            reader.session.didAppear()
            reader.session.recordBridgeEvent("snapshot:opened-resize")
            scheduleReturnSnapshotPreparation()
        } else {
            cancelReturn()
        }
    }

    private func tearDown() {
        guard phase != .closed else { return }
        phase = .closed
        animator?.stopAnimation(true)
        animator = nil
        invalidatePreparedReturnSnapshot()
        reader.session.onVisualStateChanged = nil
        returnCover = nil
        flight?.removeFromSuperview()
        flight = nil
        reader.view.isHidden = false
        reader.view.alpha = 1
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

    private func sourceGeometry(in target: UIWindow, captureCover: Bool = true) -> (rect: CGRect, cover: UIView?, cornerRadius: CGFloat)? {
        guard !UIAccessibility.isReduceMotionEnabled, let anchor = resolveSource(),
              let sourceWindow, anchor.window === sourceWindow else { return nil }
        let rect = anchor.convert(anchor.bounds, to: target)
        guard rect.width > 1, rect.height > 1,
              target.bounds.intersection(rect).width * target.bounds.intersection(rect).height >= rect.width * rect.height * 0.9
        else { return nil }
        // The registered anchor is transparent. Capture its hosting surface without hiding or mutating it.
        let cover = captureCover ? (anchor.superview ?? anchor).snapshotView(afterScreenUpdates: false) : returnCover
        return (rect, cover, min((anchor.superview ?? anchor).layer.cornerRadius, min(rect.width, rect.height) / 2))
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
            case .began:
                beginReturn(interactive: true)
                returnProgressAtGestureStart = animator?.fractionComplete ?? 0
            case .changed:
                updateReturn(progress: returnProgressAtGestureStart + translation.x / max(host.view.bounds.width, 1))
            case .ended:
                let progress = returnProgressAtGestureStart + translation.x / max(host.view.bounds.width, 1)
                updateReturn(progress: progress)
                endReturn(completes: progress + velocity.x * 0.15 / max(host.view.bounds.width, 1) > 0.32,
                    velocity: velocity.x)
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
        guard phase == .reading || phase == .opening || (phase == .returning && interactiveReturn),
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
    static func releaseVelocity(progress: CGFloat, velocity: CGFloat, width: CGFloat, completes: Bool) -> CGVector {
        guard progress.isFinite, velocity.isFinite, width.isFinite, width > 0 else { return .zero }
        let remaining = (completes ? 1 : 0) - min(max(progress, 0), 1)
        guard abs(remaining) > 0.001 else { return .zero }
        let normalized = min(max(velocity / width / remaining, -8), 8)
        return CGVector(dx: normalized, dy: normalized)
    }

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
