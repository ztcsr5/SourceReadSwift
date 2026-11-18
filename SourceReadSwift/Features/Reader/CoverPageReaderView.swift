import SwiftUI
import UIKit

enum CoverPageTurnStyle: Equatable {
    case cover
    case slide
    case dissolve
    case stacked
    case ripple
    case curl
    case verticalSlide
    case parallax
    case wipe
    case split
    case perspective
    case cube

    var usesReveal: Bool { self != .cover && self != .slide && self != .curl }
}

/// UIKit owns displacement. SwiftUI supplies immutable page snapshots, never
/// a per-frame translation. Only three pages participate in the gesture;
/// two further snapshots can be warmed while idle, outside the visible stack.
struct CoverPageReaderView: UIViewControllerRepresentable {
    var turnRequest: ReaderPageTurnRequest? = nil
    var pageIdentity: String
    var contentRevision: String
    var previousIdentity: String = ""
    var currentIdentity: String = ""
    var nextIdentity: String = ""
    var previous2Identity: String = ""
    var next2Identity: String = ""
    var hasPrevious: Bool
    var hasNext: Bool
    var previous: AnyView?
    var current: AnyView
    var next: AnyView?
    var previous2: AnyView?
    var next2: AnyView?
    var onCommit: (Int) -> Void
    var onInteractionChange: (Bool) -> Void
    var onPageInstalled: ((String) -> Void)? = nil
    var onPageContainerLayout: ((CGSize, CGFloat) -> Void)?
    var turnStyle: CoverPageTurnStyle = .cover
    var pageBackgroundColor: UIColor?
    var userInterfaceStyle: UIUserInterfaceStyle = .unspecified

    func makeUIViewController(context: Context) -> CoverPageHostController {
        let controller = CoverPageHostController()
        updateUIViewController(controller, context: context)
        return controller
    }

    func updateUIViewController(_ controller: CoverPageHostController, context: Context) {
        controller.apply(
            pageIdentity: pageIdentity, contentRevision: contentRevision,
            previousIdentity: previousIdentity, currentIdentity: currentIdentity, nextIdentity: nextIdentity,
            previous2Identity: previous2Identity, next2Identity: next2Identity,
            hasPrevious: hasPrevious, hasNext: hasNext,
            previous: previous, current: current, next: next, previous2: previous2, next2: next2,
            onCommit: onCommit, onInteractionChange: onInteractionChange, onPageInstalled: onPageInstalled,
            onPageContainerLayout: onPageContainerLayout, turnStyle: turnStyle,
            pageBackgroundColor: pageBackgroundColor, userInterfaceStyle: userInterfaceStyle
        )
        controller.requestTurn(turnRequest)
    }

    static func dismantleUIViewController(_ controller: CoverPageHostController, coordinator: ()) {
        controller.tearDown()
    }
}

enum ReaderPanTurnPolicy {
    static func direction(translation: CGFloat, velocity: CGFloat, width: CGFloat, hasPrevious: Bool, hasNext: Bool) -> Int {
        guard width > 1 else { return 0 }
        let projected = translation + velocity * 0.12
        let threshold = min(width * 0.25, 96)
        if projected < -threshold, hasNext { return 1 }
        if projected > threshold, hasPrevious { return -1 }
        return 0
    }
}

final class CoverPageHostController: UIViewController, UIGestureRecognizerDelegate {
    private static let requestedTurnDuration: TimeInterval = 0.36
    private static let requestedRevealTurnDuration: TimeInterval = 0.44
    private static let requestedCurlTurnDuration: TimeInterval = 0.42
    private static let cadencePulseKey = "reader.cover.proMotionPulse"

    private struct Window {
        let identity: String
        let revision: String
        let keys: [String]
        let roots: [AnyView?]
        let hasPrevious: Bool
        let hasNext: Bool
        let style: CoverPageTurnStyle
        let paper: UIColor?
        let appearance: UIUserInterfaceStyle
    }
    private var window: Window?
    private var pendingWindow: Window?
    private var idlePublicationGeneration = 0
    private var hosts: [String: UIHostingController<AnyView>] = [:]
    private var active: [UIHostingController<AnyView>?] = []
    private(set) var animator: UIViewPropertyAnimator?
    private var isAnimating: Bool { animator != nil || curl?.isAnimating == true }
    private var animationGeneration = 0
    private var warmupGeneration = 0
    private var isTornDown = false
    private var awaitingIdentityChangeFrom: String?
    private var onCommit: ((Int) -> Void)?
    private var onInteractionChange: ((Bool) -> Void)?
    private var onPageInstalled: ((String) -> Void)?
    private var onPageContainerLayout: ((CGSize, CGFloat) -> Void)?
    private var lastSize: CGSize = .zero
    private var lastMinY: CGFloat = .greatestFiniteMagnitude
    private var translation: CGFloat = 0
    private var rawTranslation: CGFloat = 0
    private let pageReveal = ReaderPageRevealSurface()
    private let coverEdgeShadow = CoverEdgeShadowView()
    private var curl: ReaderCurlSurface?
    private struct CompletedGesture {
        let translation: CGFloat
        let velocity: CGFloat
        let cancelled: Bool
    }
    private var completedGestures: [CompletedGesture] = []
    private var queuedTurnRequest: ReaderPageTurnRequest?
    private(set) var isDragging = false
    var visiblePageIdentity: String { window?.identity ?? "" }
    var installedPageKeys: [String] { window?.keys ?? [] }
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))

    override func viewDidLoad() {
        super.viewDidLoad()
        view.clipsToBounds = true
        pan.delegate = self
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        view.addGestureRecognizer(pan)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isTornDown else { return }
        let size = view.bounds.size
        guard size.width > 1, size.height > 1 else { return }
        if lastSize != size {
            curl?.invalidate()
            sizePagesIfNeeded()
            cancelInteraction()
            scheduleWarmup()
        }
        let minY = view.convert(view.bounds, to: nil).minY
        guard size != lastSize || abs(minY - lastMinY) > 0.5 else { return }
        lastSize = size
        lastMinY = minY
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isTornDown else { return }
            self.onPageContainerLayout?(size, minY)
        }
    }

    func apply(
        pageIdentity: String, contentRevision: String,
        previousIdentity: String, currentIdentity: String, nextIdentity: String,
        previous2Identity: String = "", next2Identity: String = "",
        hasPrevious: Bool, hasNext: Bool,
        previous: AnyView?, current: AnyView, next: AnyView?, previous2: AnyView? = nil, next2: AnyView? = nil,
        onCommit: @escaping (Int) -> Void, onInteractionChange: @escaping (Bool) -> Void,
        onPageInstalled: ((String) -> Void)? = nil,
        onPageContainerLayout: ((CGSize, CGFloat) -> Void)?, turnStyle: CoverPageTurnStyle = .cover,
        pageBackgroundColor: UIColor? = nil, userInterfaceStyle: UIUserInterfaceStyle = .unspecified
    ) {
        guard !isTornDown else { return }
        loadViewIfNeeded()
        self.onCommit = onCommit
        self.onInteractionChange = onInteractionChange
        self.onPageInstalled = onPageInstalled
        self.onPageContainerLayout = onPageContainerLayout
        let nextWindow = Window(identity: pageIdentity, revision: contentRevision,
                                keys: [previous2Identity, previousIdentity, currentIdentity, nextIdentity, next2Identity],
                                roots: [previous2, previous, current, next, next2],
                                hasPrevious: hasPrevious, hasNext: hasNext, style: turnStyle,
                                paper: pageBackgroundColor, appearance: userInterfaceStyle)
        if let oldIdentity = awaitingIdentityChangeFrom {
            // Ignore a SwiftUI pass with the pre-commit model. A new drag may
            // already be collecting input, but its page must be installed first.
            guard pageIdentity != oldIdentity else { pendingWindow = nextWindow; return }
            awaitingIdentityChangeFrom = nil
        } else if isDragging || isAnimating {
            pendingWindow = nextWindow
            return
        }
        let wasAwaitingLayout = window?.identity != nextWindow.identity || window?.keys != nextWindow.keys
            || window?.revision != nextWindow.revision || window?.style != nextWindow.style
            || window?.hasPrevious != nextWindow.hasPrevious || window?.hasNext != nextWindow.hasNext
            || window?.appearance != nextWindow.appearance || window?.paper != nextWindow.paper
        if wasAwaitingLayout { install(nextWindow) }
        // Completed flicks belong to their own immutable input, not the finger
        // that may already be dragging again while SwiftUI delivers this model.
        while !completedGestures.isEmpty {
            let gesture = completedGestures.removeFirst()
            let direction = gesture.cancelled ? 0 : ReaderPanTurnPolicy.direction(
                translation: gesture.translation, velocity: gesture.velocity, width: view.bounds.width,
                hasPrevious: nextWindow.hasPrevious, hasNext: nextWindow.hasNext
            )
            if direction != 0 {
                translation = 0
                layoutPages(translation: 0)
                awaitingIdentityChangeFrom = nextWindow.identity
                let generation = animationGeneration
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isTornDown, self.animationGeneration == generation,
                          self.awaitingIdentityChangeFrom == nextWindow.identity,
                          self.window?.identity == nextWindow.identity else { return }
                    self.onCommit?(direction)
                }
                return
            }
        }
        if isDragging {
            updateInteraction(translation: rawTranslation)
        } else if wasAwaitingLayout {
            // updateUIViewController must not synchronously flush SwiftUI
            // @State. Recheck ownership after the representable update ends.
            idlePublicationGeneration += 1
            let idleGeneration = idlePublicationGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isTornDown, !self.isDragging, !self.isAnimating,
                      self.idlePublicationGeneration == idleGeneration,
                      self.awaitingIdentityChangeFrom == nil, self.completedGestures.isEmpty else { return }
                self.onInteractionChange?(false)
            }
        }
    }

    private func install(_ next: Window) {
        guard !isTornDown else { return }
        let identityChanged = window?.identity != next.identity
        let changed = window?.keys != next.keys || window?.revision != next.revision || window?.style != next.style
        let oldRevision = window?.revision
        if window?.revision != next.revision || window?.style != next.style
            || window?.appearance != next.appearance || window?.paper != next.paper { curl?.invalidate() }
        curl?.reset(pages: active.compactMap { $0?.view })
        if next.style == .curl {
            if curl == nil { curl = ReaderCurlSurface() }
        } else {
            curl = nil
        }
        window = next
        pendingWindow = nil
        view.backgroundColor = next.paper ?? .clear
        overrideUserInterfaceStyle = next.appearance
        if changed {
            warmupGeneration += 1
            let retained = Set(next.keys.filter { !$0.isEmpty })
            for key in Array(hosts.keys) where !retained.contains(key) {
                guard let host = hosts.removeValue(forKey: key) else { continue }
                host.willMove(toParent: nil)
                host.view.removeFromSuperview()
                host.removeFromParent()
            }
            active = next.keys.enumerated().map { index, key in
                guard !key.isEmpty, let root = next.roots[index] else { return nil }
                if let host = hosts[key] {
                    if oldRevision != next.revision { host.rootView = root }
                    return host
                }
                // Distant pages are not visible in this transaction. Mounting
                // their hosting trees here steals the first frame after a turn.
                guard index > 0 && index < 4 else { return nil }
                return mountPage(key: key, root: root)
            }
        }
        for (index, host) in active.enumerated() {
            host?.view.backgroundColor = next.paper ?? .clear
            host?.view.isOpaque = next.paper != nil
            host?.overrideUserInterfaceStyle = next.appearance
            host?.view.isHidden = index == 0 || index == 4
        }
        sizePagesIfNeeded()
        curl?.retain(pages: [active[2], active[3]].compactMap { $0?.view })
        layoutPages(translation: translation)
        scheduleWarmup()
        if identityChanged {
            let identity = next.identity
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isTornDown, self.window?.identity == identity,
                      self.awaitingIdentityChangeFrom == nil, !self.isDragging, !self.isAnimating else { return }
                self.onPageInstalled?(identity)
            }
        }
    }

    private func sizePagesIfNeeded() {
        let size = view.bounds.size
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        for host in active {
            guard let page = host?.view, page.bounds.size != size else { continue }
            // Never set frame while a nonidentity transform is active.
            // Hosting geometry changes only on installation or a viewport resize.
            page.bounds = CGRect(origin: .zero, size: size)
            page.center = center
            page.layer.shadowOpacity = 0
            page.layer.shadowRadius = 0
            page.layer.shadowPath = nil
        }
        coverEdgeShadow.updateHeight(size.height)
    }

    private func layoutPages(translation x: CGFloat) {
        guard !isTornDown, active.count == 5, let window else { return }
        let width = view.bounds.width
        let previous = active[1]?.view
        let current = active[2]?.view
        let next = active[3]?.view
        if let curl {
            coverEdgeShadow.isHidden = true
            pageReveal.reset(pages: [previous, current, next])
            let isUnavailable = (x < 0 && !window.hasNext) || (x > 0 && !window.hasPrevious)
            if (x == 0 && !isDragging && !isAnimating) || isUnavailable {
                curl.reset(pages: [previous, current, next])
                previous?.alpha = 0
                next?.alpha = 0
                current?.alpha = 1
                current?.isUserInteractionEnabled = true
                current?.accessibilityElementsHidden = false
                for page in [previous, next] {
                    page?.isUserInteractionEnabled = false
                    page?.accessibilityElementsHidden = true
                }
            } else {
                curl.apply(translation: x, in: view, pages: [previous, current, next])
            }
            return
        }
        if window.style.usesReveal {
            coverEdgeShadow.isHidden = true
            pageReveal.apply(style: window.style, translation: x, in: view,
                             pages: [previous, current, next])
            return
        }
        pageReveal.reset(pages: [previous, current, next])
        if window.style == .slide {
            coverEdgeShadow.isHidden = true
            previous?.transform = CGAffineTransform(translationX: x - width, y: 0)
            current?.transform = CGAffineTransform(translationX: x, y: 0)
            next?.transform = CGAffineTransform(translationX: x + width, y: 0)
            for page in [previous, current, next] {
                page?.layer.shadowOpacity = 0
                if page?.layer.shouldRasterize == true { page?.layer.shouldRasterize = false }
            }
        } else {
            // Stable z-ordering: next (back) -> current (middle) -> previous (front)
            // Pure GPU translation + lightweight 20pt gradient edge shadow avoids
            // full-screen dynamic shadow offscreen passes so cover tracks at 120Hz.
            if let next, view.subviews.first !== next { view.sendSubviewToBack(next) }
            if let previous, view.subviews.last !== previous {
                if let current { view.bringSubviewToFront(current) }
                view.bringSubviewToFront(previous)
            }
            if coverEdgeShadow.superview !== view {
                view.addSubview(coverEdgeShadow)
            }
            if view.subviews.last !== coverEdgeShadow {
                view.bringSubviewToFront(coverEdgeShadow)
            }
            previous?.transform = CGAffineTransform(translationX: x > 0 ? x - width : -width, y: 0)
            current?.transform = CGAffineTransform(translationX: min(x, 0), y: 0)
            next?.transform = .identity
            for page in [previous, current, next] {
                if page?.layer.shadowOpacity != 0 { page?.layer.shadowOpacity = 0 }
                if page?.layer.shouldRasterize == true { page?.layer.shouldRasterize = false }
            }
            let isMoving = abs(x) > 0.5
            coverEdgeShadow.isHidden = !isMoving
            if isMoving {
                let edgeX = x > 0 ? x : (width + x)
                coverEdgeShadow.center = CGPoint(x: edgeX + coverEdgeShadow.bounds.width * 0.5, y: view.bounds.midY)
                let progress = min(abs(x) / max(width, 1), 1)
                coverEdgeShadow.alpha = max(0, 1 - progress * 0.65)
            }
        }
    }

    private func mountPage(key: String, root: AnyView) -> UIHostingController<AnyView> {
        let host = UIHostingController(rootView: root)
        host.view.accessibilityIdentifier = "reader.page.\(key)"
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        hosts[key] = host
        return host
    }

    private func scheduleWarmup() {
        let generation = warmupGeneration
        if curl != nil {
            // Let the committed page paint before rasterizing its sheet.
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(25)) { [weak self] in
                guard let self, self.canWarmPages(generation: generation) else { return }
                self.warmCurrentCurlPage()
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(15)) { [weak self] in
                    guard let self, self.canWarmPages(generation: generation) else { return }
                    self.warmNextCurlPage()
                    self.warmPreviousCurlPage()
                }
            }
        }
        let staggerSteps: [(index: Int, delayMs: Int, needsMount: Bool)] = [
            (3, 0, false),
            (1, 14, false),
            (4, 28, true),
            (0, 44, true)
        ]
        for step in staggerSteps {
            let delay: DispatchTimeInterval = .milliseconds(step.delayMs)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.canWarmPages(generation: generation) else { return }
                if step.needsMount {
                    self.mountDistantPageIfNeeded(at: step.index)
                } else {
                    self.active[step.index]?.view.layoutIfNeeded()
                }
            }
        }
    }

    private func canWarmPages(generation: Int) -> Bool {
        !isTornDown && warmupGeneration == generation && !isDragging
            && !isAnimating && awaitingIdentityChangeFrom == nil && active.count == 5
    }

    private func warmCurrentCurlPage() {
        guard let curl, let page = active[2]?.view else { return }
        curl.warm(page: page, key: page.accessibilityIdentifier ?? "")
    }

    private func warmNextCurlPage() {
        guard let curl, let page = active[3]?.view else { return }
        curl.warm(page: page, key: page.accessibilityIdentifier ?? "")
    }

    private func warmPreviousCurlPage() {
        guard let curl, let page = active[1]?.view else { return }
        curl.warm(page: page, key: page.accessibilityIdentifier ?? "")
    }

    private func mountDistantPageIfNeeded(at index: Int) {
        guard let window, active[index] == nil, !window.keys[index].isEmpty, let root = window.roots[index] else { return }
        let host = mountPage(key: window.keys[index], root: root)
        active[index] = host
        host.view.backgroundColor = window.paper ?? .clear
        host.view.isOpaque = window.paper != nil
        host.overrideUserInterfaceStyle = window.appearance
        host.view.isHidden = true
        sizePagesIfNeeded()
        host.view.layoutIfNeeded()
    }

    func requestTurn(_ request: ReaderPageTurnRequest?) {
        guard !isTornDown else { return }
        guard let request else {
            queuedTurnRequest?.discard()
            queuedTurnRequest = nil
            return
        }
        guard queuedTurnRequest !== request, !request.isConsumed else { return }
        queuedTurnRequest?.discard()
        guard let window else {
            request.discard()
            return
        }
        let identity = window.identity
        let style = window.style
        let generation = animationGeneration
        queuedTurnRequest = request
        DispatchQueue.main.async { [weak self] in
            defer {
                request.discard()
                if let self, self.queuedTurnRequest === request { self.queuedTurnRequest = nil }
            }
            guard let self, !self.isTornDown, self.queuedTurnRequest === request,
                  self.animationGeneration == generation,
                  !self.isDragging, !self.isAnimating,
                  self.awaitingIdentityChangeFrom == nil,
                  let window = self.window, window.identity == identity, window.style == style,
                  request.direction > 0 ? window.hasNext : window.hasPrevious,
                  request.claim(pageIdentity: identity, style: style) else { return }
            let animated = !UIAccessibility.isReduceMotionEnabled
            // A cold tap must not rasterize a full page on the main thread.
            // The idle prewarm supplies the curl; a cold miss uses the animated fallback.
            self.beginInteraction()
            // The pan policy projects velocity into a complete turn. Starting
            // at zero retains the swipe's cover/slide displacement and shadows.
            let velocity = -CGFloat(request.direction) * max(self.view.bounds.width, 1) * 10
            let requestedDuration: TimeInterval
            switch window.style {
            case .curl:
                requestedDuration = Self.requestedCurlTurnDuration
            case .perspective, .cube, .dissolve, .ripple, .wipe, .split:
                requestedDuration = Self.requestedRevealTurnDuration
            default:
                requestedDuration = Self.requestedTurnDuration
            }
            self.endInteraction(velocity: velocity, animated: animated, durationOverride: requestedDuration)
        }
    }

    func beginInteraction() {
        guard !isTornDown else { return }
        isDragging = true
        translation = 0
        rawTranslation = 0
        warmupGeneration += 1
        onInteractionChange?(true)
        guard !isTornDown else { return }
        if let animator {
            animator.stopAnimation(false)
            animator.finishAnimation(at: .end)
        } else { curl?.finishAnimation() }
    }

    func updateInteraction(translation raw: CGFloat) {
        guard !isTornDown else { return }
        rawTranslation = raw
        guard isDragging, awaitingIdentityChangeFrom == nil, let window else { return }
        let width = max(view.bounds.width, 1)
        var x = min(max(raw, -width), width)
        if (x < 0 && !window.hasNext) || (x > 0 && !window.hasPrevious) { x *= 0.18 }
        translation = x
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutPages(translation: x)
        CATransaction.commit()
    }

    func endInteraction(velocity: CGFloat, cancelled: Bool = false, animated: Bool = true,
                        durationOverride: TimeInterval? = nil) {
        guard !isTornDown, isDragging else { return }
        isDragging = false
        if awaitingIdentityChangeFrom != nil {
            completedGestures.append(CompletedGesture(translation: rawTranslation, velocity: velocity, cancelled: cancelled))
            return
        }
        guard let window else { return }
        let direction = cancelled ? 0 : ReaderPanTurnPolicy.direction(
            translation: translation, velocity: velocity, width: view.bounds.width,
            hasPrevious: window.hasPrevious, hasNext: window.hasNext
        )
        animationGeneration += 1
        let generation = animationGeneration
        let target = -CGFloat(direction) * view.bounds.width
        let completion: () -> Void = { [weak self] in
            guard let self, !self.isTornDown, self.animationGeneration == generation else { return }
            self.animator = nil
            self.translation = 0
            if direction != 0 {
                self.awaitingIdentityChangeFrom = window.identity
                self.onCommit?(direction)
            } else {
                self.layoutPages(translation: 0)
                if let pending = self.pendingWindow { self.install(pending) }
                self.onInteractionChange?(self.isDragging)
                self.scheduleWarmup()
            }
        }
        if !animated || abs(target - translation) < 0.5 {
            layoutPages(translation: target)
            completion()
            return
        }
        let distance = abs(target - translation)
        let duration: TimeInterval
        if let durationOverride {
            duration = durationOverride
        } else {
            switch window.style {
            case .curl:
                duration = min(max(Double(distance / max(abs(velocity), 680)), 0.34), 0.46)
            case .perspective, .cube, .dissolve, .ripple, .wipe, .split:
                duration = min(max(Double(distance / max(abs(velocity), 520)), 0.36), 0.48)
            default:
                duration = min(max(Double(distance / max(abs(velocity), 640)), 0.30), 0.42)
            }
        }
        if usesPageReveal, direction != 0, translation * target < 0 {
            // The projected velocity can reverse a partially revealed page. Close
            // its mask before reparenting it to the opposite neighbour at rest.
            let returnDuration = min(max(Double(abs(translation) / max(abs(velocity), 900)), 0.06), 0.12)
            animatePages(to: 0, duration: returnDuration) { [weak self] in
                guard let self, !self.isTornDown, self.animationGeneration == generation else { return }
                self.translation = 0
                self.preparePageReveal(direction: direction)
                if self.isDragging {
                    // A new finger gesture finishes the previous turn just as it
                    // does for the original one-segment cover/slide animator.
                    self.layoutPages(translation: target)
                    completion()
                } else {
                    self.animatePages(to: target, duration: duration, completion: completion)
                }
            }
            return
        }
        if usesPageReveal, direction != 0, translation == 0 {
            preparePageReveal(direction: direction)
        }
        animatePages(to: target, duration: duration, completion: completion)
    }

    private var usesPageReveal: Bool {
        window.map { $0.style.usesReveal || $0.style == .curl } ?? false
    }

    private func preparePageReveal(direction: Int) {
        guard usesPageReveal, active.count == 5, let window else { return }
        if let curl {
            curl.prepare(direction: direction, in: view, pages: [active[1]?.view, active[2]?.view, active[3]?.view])
            return
        }
        pageReveal.prepare(direction: direction, style: window.style, in: view,
                           pages: [active[1]?.view, active[2]?.view, active[3]?.view])
    }

    private func animatePages(to target: CGFloat, duration: TimeInterval, completion: @escaping () -> Void) {
        if curl?.animate(to: target, duration: duration, completion: completion) == true { return }
        // Request explicit 120Hz cadence from Core Animation during deceleration tails.
        if #available(iOS 15.0, *), let screen = view.window?.screen, screen.maximumFramesPerSecond >= 120 {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 1.0
            pulse.duration = duration
            pulse.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
            view.layer.add(pulse, forKey: Self.cadencePulseKey)
        }
        let animator = UIViewPropertyAnimator(
            duration: duration,
            controlPoint1: CGPoint(x: 0.22, y: 0.61),
            controlPoint2: CGPoint(x: 0.36, y: 1.0)
        ) { [weak self] in
            self?.layoutPages(translation: target)
        }
        self.animator = animator
        animator.addCompletion { [weak self] _ in
            self?.view.layer.removeAnimation(forKey: Self.cadencePulseKey)
            completion()
        }
        animator.startAnimation()
    }

    func cancelInteraction() {
        guard !isTornDown else { return }
        animationGeneration += 1
        warmupGeneration += 1
        animator?.stopAnimation(true)
        animator = nil
        curl?.cancelAnimation()
        isDragging = false
        completedGestures.removeAll()
        rawTranslation = 0
        awaitingIdentityChangeFrom = nil
        translation = 0
        if let pending = pendingWindow { install(pending) }
        layoutPages(translation: 0)
        // Resize/layout can also cancel a turn while SwiftUI owns its graph.
        // Publish only after that transaction, unless a new gesture took over.
        let generation = animationGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isTornDown, self.animationGeneration == generation,
                  !self.isDragging, !self.isAnimating,
                  self.awaitingIdentityChangeFrom == nil else { return }
            self.onInteractionChange?(false)
        }
    }

    /// SwiftUI dismantles this controller while holding exclusive graph access.
    /// A reusable cancel may publish state or install pending hosted pages; a
    /// terminal teardown must do neither (iOS 17 aborts in swift_beginAccess).
    func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        idlePublicationGeneration += 1
        onCommit = nil
        onInteractionChange = nil
        onPageInstalled = nil
        onPageContainerLayout = nil
        animationGeneration += 1
        warmupGeneration += 1
        animator?.stopAnimation(true)
        animator = nil
        isDragging = false
        completedGestures.removeAll()
        pendingWindow = nil
        awaitingIdentityChangeFrom = nil
        rawTranslation = 0
        translation = 0
        if isViewLoaded { pan.isEnabled = false }
        curl?.invalidate()
        // Let UIKit dispose of the children. Removing/replacing hosting roots
        // here would re-enter the very SwiftUI graph being dismantled.
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began: beginInteraction()
        case .changed: updateInteraction(translation: normalizedDisplacement(gesture.translation(in: view)))
        case .ended:
            updateInteraction(translation: normalizedDisplacement(gesture.translation(in: view)))
            endInteraction(velocity: normalizedDisplacement(gesture.velocity(in: view)),
                           animated: !UIAccessibility.isReduceMotionEnabled)
        case .cancelled, .failed: endInteraction(velocity: 0, cancelled: true)
        default: break
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard !isTornDown else { return false }
        let velocity = pan.velocity(in: view)
        if window?.style == .verticalSlide { return abs(velocity.y) > abs(velocity.x) }
        let location = pan.location(in: view)
        let isRTL = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let leadingDistance = isRTL ? view.bounds.maxX - location.x : location.x - view.bounds.minX
        if leadingDistance >= 0, leadingDistance <= ReaderEdgeTapPolicy.reservedLeadingWidth,
           (isRTL ? -velocity.x : velocity.x) > abs(velocity.y) {
            return false
        }
        return abs(velocity.x) > abs(velocity.y)
    }

    private func normalizedDisplacement(_ point: CGPoint) -> CGFloat {
        window?.style == .verticalSlide ? point.y * view.bounds.width / max(view.bounds.height, 1) : point.x
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard !isTornDown else { return false }
        var candidate = touch.view
        while let view = candidate {
            if view is UIControl { return false }
            if let text = view as? UITextView, text.isSelectable { return false }
            candidate = view.superview
        }
        return true
    }
}

private final class CoverEdgeShadowView: UIView {
    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 20, height: max(frame.height, 1)))
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        isHidden = true
        gradient.colors = [
            UIColor.black.withAlphaComponent(0.16).cgColor,
            UIColor.black.withAlphaComponent(0.05).cgColor,
            UIColor.clear.cgColor
        ]
        gradient.locations = [0, 0.45, 1]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(gradient)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateHeight(_ height: CGFloat) {
        let clamped = max(height, 1)
        guard abs(bounds.height - clamped) > 0.5 else { return }
        bounds = CGRect(x: 0, y: 0, width: 20, height: clamped)
        gradient.frame = bounds
    }
}
