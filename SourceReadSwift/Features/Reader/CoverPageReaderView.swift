import SwiftUI
import UIKit

enum CoverPageTurnStyle {
    case cover
    case slide
}

/// UIKit owns displacement. SwiftUI supplies immutable page snapshots, never
/// a per-frame translation. Only three pages participate in the gesture;
/// two further snapshots can be warmed while idle, outside the visible stack.
struct CoverPageReaderView: UIViewControllerRepresentable {
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
            onCommit: onCommit, onInteractionChange: onInteractionChange,
            onPageContainerLayout: onPageContainerLayout, turnStyle: turnStyle,
            pageBackgroundColor: pageBackgroundColor, userInterfaceStyle: userInterfaceStyle
        )
    }

    static func dismantleUIViewController(_ controller: CoverPageHostController, coordinator: ()) {
        controller.cancelInteraction()
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
    private var hosts: [String: UIHostingController<AnyView>] = [:]
    private var active: [UIHostingController<AnyView>?] = []
    private var animator: UIViewPropertyAnimator?
    private var animationGeneration = 0
    private var warmupGeneration = 0
    private var awaitingIdentityChangeFrom: String?
    private var onCommit: ((Int) -> Void)?
    private var onInteractionChange: ((Bool) -> Void)?
    private var onPageContainerLayout: ((CGSize, CGFloat) -> Void)?
    private var lastSize: CGSize = .zero
    private var lastMinY: CGFloat = .greatestFiniteMagnitude
    private var translation: CGFloat = 0
    private var rawTranslation: CGFloat = 0
    private struct CompletedGesture {
        let translation: CGFloat
        let velocity: CGFloat
        let cancelled: Bool
    }
    private var completedGestures: [CompletedGesture] = []
    private(set) var isDragging = false
    var visiblePageIdentity: String { window?.identity ?? "" }
    var installedPageKeys: [String] { window?.keys ?? [] }
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))

    override func viewDidLoad() {
        super.viewDidLoad()
        view.clipsToBounds = true
        pan.delegate = self
        pan.cancelsTouchesInView = false
        view.addGestureRecognizer(pan)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        guard size.width > 1, size.height > 1 else { return }
        if lastSize != size {
            cancelInteraction()
            layoutPages(translation: 0)
        }
        let minY = view.convert(view.bounds, to: nil).minY
        guard size != lastSize || abs(minY - lastMinY) > 0.5 else { return }
        lastSize = size
        lastMinY = minY
        DispatchQueue.main.async { [weak self] in self?.onPageContainerLayout?(size, minY) }
    }

    func apply(
        pageIdentity: String, contentRevision: String,
        previousIdentity: String, currentIdentity: String, nextIdentity: String,
        previous2Identity: String = "", next2Identity: String = "",
        hasPrevious: Bool, hasNext: Bool,
        previous: AnyView?, current: AnyView, next: AnyView?, previous2: AnyView? = nil, next2: AnyView? = nil,
        onCommit: @escaping (Int) -> Void, onInteractionChange: @escaping (Bool) -> Void,
        onPageContainerLayout: ((CGSize, CGFloat) -> Void)?, turnStyle: CoverPageTurnStyle = .cover,
        pageBackgroundColor: UIColor? = nil, userInterfaceStyle: UIUserInterfaceStyle = .unspecified
    ) {
        loadViewIfNeeded()
        self.onCommit = onCommit
        self.onInteractionChange = onInteractionChange
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
        } else if isDragging || animator != nil {
            pendingWindow = nextWindow
            return
        }
        install(nextWindow)
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
                    guard let self, self.animationGeneration == generation,
                          self.awaitingIdentityChangeFrom == nextWindow.identity,
                          self.window?.identity == nextWindow.identity else { return }
                    self.onCommit?(direction)
                }
                return
            }
        }
        if isDragging {
            updateInteraction(translation: rawTranslation)
        } else {
            // updateUIViewController must not synchronously flush SwiftUI
            // @State. Recheck ownership after the representable update ends.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isDragging, self.animator == nil,
                      self.awaitingIdentityChangeFrom == nil, self.completedGestures.isEmpty else { return }
                self.onInteractionChange?(false)
            }
        }
    }

    private func install(_ next: Window) {
        let changed = window?.keys != next.keys || window?.revision != next.revision || window?.style != next.style
        let oldRevision = window?.revision
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
                let host = UIHostingController(rootView: root)
                host.view.accessibilityIdentifier = "reader.page.\(key)"
                addChild(host)
                view.addSubview(host.view)
                host.didMove(toParent: self)
                hosts[key] = host
                return host
            }
        }
        for (index, host) in active.enumerated() {
            host?.view.backgroundColor = next.paper ?? .clear
            host?.view.isOpaque = next.paper != nil
            host?.overrideUserInterfaceStyle = next.appearance
            host?.view.isHidden = index == 0 || index == 4
        }
        layoutPages(translation: translation)
        scheduleWarmup()
    }

    private func layoutPages(translation x: CGFloat) {
        guard active.count == 5, let window else { return }
        let width = view.bounds.width
        for host in active { host?.view.frame = view.bounds }
        let previous = active[1]?.view
        let current = active[2]?.view
        let next = active[3]?.view
        if window.style == .slide {
            previous?.frame.origin.x = x - width
            current?.frame.origin.x = x
            next?.frame.origin.x = x + width
            for page in [previous, current, next] { page?.layer.shadowOpacity = 0 }
        } else {
            if let next { view.sendSubviewToBack(next) }
            if let current { view.bringSubviewToFront(current) }
            if let previous { view.bringSubviewToFront(previous) }
            previous?.frame.origin.x = x > 0 ? x - width : -width
            current?.frame.origin.x = min(x, 0)
            next?.frame.origin.x = 0
            for page in [previous, current] {
                page?.layer.shadowColor = UIColor.black.cgColor
                page?.layer.shadowOpacity = abs(x) > 0.5 ? 0.18 : 0
                page?.layer.shadowRadius = 5
                page?.layer.shadowOffset = CGSize(width: 3, height: 0)
                page?.layer.shadowPath = UIBezierPath(rect: view.bounds).cgPath
            }
        }
    }

    private func scheduleWarmup() {
        let generation = warmupGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.warmupGeneration == generation, !self.isDragging,
                  self.animator == nil, self.awaitingIdentityChangeFrom == nil else { return }
            for host in self.active { host?.view.layoutIfNeeded() }
        }
    }

    func beginInteraction() {
        isDragging = true
        translation = 0
        rawTranslation = 0
        warmupGeneration += 1
        onInteractionChange?(true)
        if let animator {
            animator.stopAnimation(false)
            animator.finishAnimation(at: .end)
        }
    }

    func updateInteraction(translation raw: CGFloat) {
        rawTranslation = raw
        guard isDragging, awaitingIdentityChangeFrom == nil, let window else { return }
        let width = max(view.bounds.width, 1)
        var x = min(max(raw, -width), width)
        if (x < 0 && !window.hasNext) || (x > 0 && !window.hasPrevious) { x *= 0.18 }
        translation = x
        layoutPages(translation: x)
    }

    func endInteraction(velocity: CGFloat, cancelled: Bool = false, animated: Bool = true) {
        guard isDragging else { return }
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
            guard let self, self.animationGeneration == generation else { return }
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
        let animator = UIViewPropertyAnimator(duration: 0.18, curve: .easeOut) { [weak self] in
            self?.layoutPages(translation: target)
        }
        self.animator = animator
        animator.addCompletion { _ in completion() }
        animator.startAnimation()
    }

    func cancelInteraction() {
        animationGeneration += 1
        warmupGeneration += 1
        animator?.stopAnimation(true)
        animator = nil
        isDragging = false
        completedGestures.removeAll()
        rawTranslation = 0
        awaitingIdentityChangeFrom = nil
        translation = 0
        if let pending = pendingWindow { install(pending) }
        layoutPages(translation: 0)
        onInteractionChange?(false)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began: beginInteraction()
        case .changed: updateInteraction(translation: gesture.translation(in: view).x)
        case .ended:
            updateInteraction(translation: gesture.translation(in: view).x)
            endInteraction(velocity: gesture.velocity(in: view).x)
        case .cancelled, .failed: endInteraction(velocity: 0, cancelled: true)
        default: break
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let velocity = pan.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var candidate = touch.view
        while let view = candidate {
            if view is UIControl { return false }
            candidate = view.superview
        }
        return true
    }
}
