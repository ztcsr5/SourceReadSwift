import SwiftUI
import UIKit

enum ReaderExitSwipePolicy {
    static func isEnabled(menuVisible: Bool, settingsVisible: Bool, coverPresented: Bool) -> Bool {
        menuVisible && !settingsVisible && !coverPresented
    }

    static func isRightward(_ movement: CGPoint) -> Bool {
        movement.x.isFinite && movement.y.isFinite
            && movement.x > 0 && movement.x > abs(movement.y) * 1.5
    }

    static func shouldFinish(translation: CGPoint, velocity: CGPoint, width: CGFloat) -> Bool {
        guard width.isFinite, width > 0, isRightward(translation) else { return false }
        let threshold = max(72, min(width * 0.22, 140))
        return translation.x >= threshold
            || (translation.x >= 32 && isRightward(velocity) && velocity.x >= 650)
    }
}

/// Only the reader's hosting subtree receives the recognizer, never the window.
/// The normal page gestures remain untouched while the reading menu is hidden.
struct ReaderExitSwipeBridge: UIViewControllerRepresentable {
    let enabled: Bool
    let onExit: () -> Void

    func makeUIViewController(context: Context) -> ReaderExitSwipeController {
        let controller = ReaderExitSwipeController()
        controller.configure(enabled: enabled, onExit: onExit)
        return controller
    }

    func updateUIViewController(_ controller: ReaderExitSwipeController, context: Context) {
        controller.configure(enabled: enabled, onExit: onExit)
    }

    static func dismantleUIViewController(_ controller: ReaderExitSwipeController, coordinator: ()) {
        controller.detach()
    }
}

final class ReaderExitSwipeController: UIViewController, UIGestureRecognizerDelegate {
    private(set) var exitEnabled = false
    private var didExit = false
    private var onExit: () -> Void = {}
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
    }

    func configure(enabled: Bool, onExit: @escaping () -> Void) {
        exitEnabled = enabled
        self.onExit = onExit
        if !enabled { didExit = false }
        edgePan.isEnabled = enabled
        if isViewLoaded { attachIfNeeded() }
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil { detach() } else { attachIfNeeded() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        attachIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        attachIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        detach()
    }

    private func attachIfNeeded() {
        guard let host = parent?.view, host !== view else { return }
        if edgePan.view !== host {
            edgePan.view?.removeGestureRecognizer(edgePan)
            host.addGestureRecognizer(edgePan)
        }
    }

    func detach() {
        edgePan.view?.removeGestureRecognizer(edgePan)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        exitEnabled && !didExit && gestureRecognizer === edgePan
            && ReaderExitSwipePolicy.isRightward(edgePan.velocity(in: edgePan.view))
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
        // Dynamic priority prevents an edge-exit swipe from also turning a page.
        guard exitEnabled, gestureRecognizer === edgePan,
              let host = edgePan.view, let other = otherGestureRecognizer.view else { return false }
        return otherGestureRecognizer !== edgePan && other.isDescendant(of: host)
    }

    @objc private func handlePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        completeSwipe(translation: gesture.translation(in: gesture.view),
                      velocity: gesture.velocity(in: gesture.view), cancelled: false)
    }

    func completeSwipe(translation: CGPoint, velocity: CGPoint, cancelled: Bool) {
        guard exitEnabled, !didExit, !cancelled,
              ReaderExitSwipePolicy.shouldFinish(translation: translation, velocity: velocity,
                                                width: edgePan.view?.bounds.width ?? 0) else { return }
        didExit = true
        onExit()
    }
}
