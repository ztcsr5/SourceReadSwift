import SwiftUI
import UIKit
import OSLog

/// Native edge return is safe in vertical prose, but must not steal page turns or text selection.
enum ReaderSystemReturnPolicy {
    static func isEnabled(isScroll: Bool, menuVisible: Bool, blocked: Bool, selectionEnabled: Bool) -> Bool {
        !blocked && (menuVisible || (isScroll && !selectionEnabled))
    }
}

enum ReaderExitSwipePolicy {
    static func isEnabled(menuVisible: Bool, settingsVisible: Bool, coverPresented: Bool) -> Bool {
        menuVisible && !settingsVisible && !coverPresented
    }

    static func isRightward(_ movement: CGPoint) -> Bool {
        movement.x.isFinite && movement.y.isFinite
            && movement.x > 0 && movement.x > abs(movement.y) * 1.5
    }

    static func isProseFallbackEnabled(reducesMotion: Bool, allowsBookReturn: Bool) -> Bool {
        reducesMotion && allowsBookReturn
    }

    static func isSystemReturnActive(_ state: UIGestureRecognizer.State) -> Bool {
        state == .began || state == .changed || state == .ended
    }

    static func shouldFinish(translation: CGPoint, velocity: CGPoint, width: CGFloat) -> Bool {
        guard width.isFinite, width > 0, isRightward(translation) else { return false }
        let threshold = max(72, min(width * 0.22, 140))
        return translation.x >= threshold
            || (translation.x >= 32 && isRightward(velocity) && velocity.x >= 650)
    }
}

/// Only the reader's hosting subtree receives the recognizer, never the window.
/// Only allowed prose/menu routes enable it; page turns and selection remain protected.
struct ReaderExitSwipeBridge: UIViewControllerRepresentable {
    let enabled: Bool
    let onExit: () -> Void
    var prefersSystemReturn = false

    func makeUIViewController(context: Context) -> ReaderExitSwipeController {
        let controller = ReaderExitSwipeController()
        controller.configure(enabled: enabled, prefersSystemReturn: prefersSystemReturn, onExit: onExit)
        return controller
    }

    func updateUIViewController(_ controller: ReaderExitSwipeController, context: Context) {
        controller.configure(enabled: enabled, prefersSystemReturn: prefersSystemReturn, onExit: onExit)
    }

    static func dismantleUIViewController(_ controller: ReaderExitSwipeController, coordinator: ()) {
        controller.detach()
    }
}

final class ReaderExitSwipeController: UIViewController, UIGestureRecognizerDelegate {
    private static let decisions = Logger(subsystem: "com.edc21.SourceReadSwift.book-passage", category: "gesture")
    private(set) var exitEnabled = false
    private var didExit = false
    private var prefersSystemReturn = false
    private var onExit: () -> Void = {}
    private(set) weak var prioritizedNavigationEdge: UIGestureRecognizer?
    #if DEBUG
    private(set) var fallbackMotionCount = 0
    private var isFallbackGestureActive = false
    private var recordedFallbackMovement = false
    #endif
    lazy var edgePan: UIScreenEdgePanGestureRecognizer = {
        let gesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        gesture.edges = .left
        gesture.name = "reader.menuSwipeExit"
        gesture.maximumNumberOfTouches = 1
        gesture.delegate = self
        gesture.isEnabled = false
        return gesture
    }()

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        #if DEBUG
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "reader.fallbackGestureEvidence"
        view.accessibilityLabel = "阅读器兜底返回输入"
        view.accessibilityValue = "0"
        #endif
    }

    func configure(enabled: Bool, prefersSystemReturn: Bool = false, onExit: @escaping () -> Void) {
        exitEnabled = enabled
        self.prefersSystemReturn = prefersSystemReturn
        self.onExit = onExit
        if !enabled { didExit = false }
        if isViewLoaded { attachIfNeeded() }
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil { detach() } else { attachIfNeeded() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        attachIfNeeded()
        if prefersSystemReturn {
            Self.decisions.notice("READY native=\(self.usesSystemReturn ? 1 : 0, privacy: .public) fallback=\(self.edgePan.isEnabled ? 1 : 0, privacy: .public)")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        attachIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        detach()
    }

    private var usesSystemReturn: Bool {
        if #available(iOS 18.0, *), prefersSystemReturn,
           let navigation = navigationController, navigation.viewControllers.count > 1 {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *), navigation.interactiveContentPopGestureRecognizer?.isEnabled == true { return true }
            #endif
            return navigation.interactivePopGestureRecognizer?.isEnabled == true
        }
        return false
    }

    private func attachIfNeeded() {
        let needsFallback = exitEnabled
        if edgePan.isEnabled != needsFallback { edgePan.isEnabled = needsFallback }
        guard let host = parent?.view, host !== view else { return }
        if edgePan.view !== host {
            edgePan.view?.removeGestureRecognizer(edgePan)
            host.addGestureRecognizer(edgePan)
        }
        if prefersSystemReturn, let nativeEdge = navigationController?.interactivePopGestureRecognizer,
           nativeEdge !== prioritizedNavigationEdge {
            // An enabled native recognizer gets first refusal; only its actual
            // failure releases this fallback. Never wait on full-content pop.
            edgePan.require(toFail: nativeEdge)
            prioritizedNavigationEdge = nativeEdge
        }
    }

    func detach() {
        edgePan.view?.removeGestureRecognizer(edgePan)
    }

    private var hasActiveSystemReturn: Bool {
        if let pop = navigationController?.interactivePopGestureRecognizer,
           ReaderExitSwipePolicy.isSystemReturnActive(pop.state) { return true }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), let pop = navigationController?.interactiveContentPopGestureRecognizer,
           ReaderExitSwipePolicy.isSystemReturnActive(pop.state) { return true }
        #endif
        return false
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard exitEnabled, !didExit, gestureRecognizer === edgePan, !hasActiveSystemReturn else { return false }
        return ReaderExitSwipePolicy.isRightward(edgePan.velocity(in: edgePan.view))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard exitEnabled, !didExit, view.window != nil,
              view.bounds.contains(touch.location(in: view)),
              parent?.presentedViewController == nil else { return false }
        var candidate = touch.view
        while let touched = candidate {
            if touched is UIControl { return false }
            if touched === edgePan.view { break }
            candidate = touched.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if otherGestureRecognizer === navigationController?.interactivePopGestureRecognizer { return false }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), otherGestureRecognizer === navigationController?.interactiveContentPopGestureRecognizer { return false }
        #endif
        // Dynamic priority prevents an edge-exit swipe from also turning a page.
        guard exitEnabled, gestureRecognizer === edgePan,
              let host = edgePan.view, let other = otherGestureRecognizer.view else { return false }
        return otherGestureRecognizer !== edgePan && other.isDescendant(of: host)
    }

    @objc private func handlePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        #if DEBUG
        switch gesture.state {
        case .began:
            isFallbackGestureActive = true
            recordedFallbackMovement = false
        case .changed:
            if isFallbackGestureActive, !recordedFallbackMovement, gesture.numberOfTouches > 0 {
                recordedFallbackMovement = true
                fallbackMotionCount += 1
                view.accessibilityValue = String(fallbackMotionCount)
            }
        case .ended, .cancelled, .failed:
            isFallbackGestureActive = false
            recordedFallbackMovement = false
        default: break
        }
        #endif
        guard gesture.state == .ended else { return }
        completeSwipe(translation: gesture.translation(in: gesture.view),
                      velocity: gesture.velocity(in: gesture.view), cancelled: false)
    }

    func completeSwipe(translation: CGPoint, velocity: CGPoint, cancelled: Bool) {
        guard exitEnabled, edgePan.isEnabled, !didExit, !cancelled, !hasActiveSystemReturn,
              ReaderExitSwipePolicy.shouldFinish(translation: translation, velocity: velocity,
                                                width: edgePan.view?.bounds.width ?? 0) else { return }
        didExit = true
        onExit()
    }
}
