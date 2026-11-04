import SwiftUI
import UIKit

/// An interactive pop may begin before UIKit removes the source from the stack.
enum ReaderNativePopPolicy {
    static func isPop(from source: UIViewController, to target: UIViewController?,
                      in navigation: UINavigationController, isInteractive: Bool) -> Bool {
        let stack = navigation.viewControllers
        return source.isMovingFromParent || !stack.contains(where: { $0 === source })
            || (isInteractive && target.map { target in stack.contains(where: { $0 === target }) } == true)
    }
}

/// Releases only this reader's tab-bar ownership when a real pop starts, restoring it on cancellation.
struct ReaderTabChromeExitBridge: UIViewControllerRepresentable {
    let owner: UUID
    @EnvironmentObject private var appState: AppState

    func makeUIViewController(context: Context) -> ReaderTabChromeExitController {
        let controller = ReaderTabChromeExitController()
        configure(controller)
        return controller
    }

    func updateUIViewController(_ controller: ReaderTabChromeExitController, context: Context) {
        configure(controller)
    }

    private func configure(_ controller: ReaderTabChromeExitController) {
        controller.configure(onLeaving: { appState.releaseTabChromeHidden(owner: owner) },
            onCancelled: { appState.acquireTabChromeHidden(owner: owner) })
    }
}

final class ReaderTabChromeExitController: UIViewController {
    private var hasPreparedExit = false
    private var onLeaving: () -> Void = {}
    private var onCancelled: () -> Void = {}

    override func loadView() {
        view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    func configure(onLeaving: @escaping () -> Void, onCancelled: @escaping () -> Void) {
        self.onLeaving = onLeaving
        self.onCancelled = onCancelled
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard let transition = transitionCoordinator,
              let source = transition.viewController(forKey: .from), belongs(to: source),
              let navigation = source.navigationController ?? navigationController,
              ReaderNativePopPolicy.isPop(from: source, to: transition.viewController(forKey: .to),
                in: navigation, isInteractive: transition.isInteractive) else { return }
        prepareForExit()
        transition.animate(alongsideTransition: nil) { [weak self] context in
            self?.finishExit(cancelled: context.isCancelled)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // A cancelled interactive pop reappears even if UIKit could not register
        // another transition completion. Reacquiring an owned token is idempotent.
        if hasPreparedExit { finishExit(cancelled: true) }
    }

    func prepareForExit() {
        guard !hasPreparedExit else { return }
        hasPreparedExit = true
        onLeaving()
    }

    func finishExit(cancelled: Bool) {
        guard hasPreparedExit else { return }
        hasPreparedExit = false
        if cancelled { onCancelled() }
    }

    private func belongs(to controller: UIViewController) -> Bool {
        var ancestor: UIViewController? = self
        while let candidate = ancestor {
            if candidate === controller { return true }
            ancestor = candidate.parent
        }
        return false
    }
}
