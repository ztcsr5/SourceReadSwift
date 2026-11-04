import SwiftUI
import UIKit
import OSLog

/// Supplies a book carrier to UIKit's existing pop, without replacing its driver or gestures.
final class ReaderBookPassageController: UIViewController {
    private static let events = Logger(subsystem: "com.edc21.SourceReadSwift.book-passage", category: "return")
    var onArrival: () -> Void = {}
    var canPrepareReturn = false
    var makeReturnSurface: () -> AnyView = { AnyView(EmptyView()) }
    private(set) var returnHost: UIHostingController<AnyView>?

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        removeReturnSurface()
        DispatchQueue.main.async { [weak self] in self?.onArrival() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard canPrepareReturn, let transition = transitionCoordinator,
              let source = transition.viewController(forKey: .from), belongs(to: source),
              let navigation = source.navigationController ?? navigationController,
              source.isMovingFromParent || !navigation.viewControllers.contains(where: { $0 === source }) else { return }
        Self.events.notice("BEGIN interactive=\(transition.isInteractive ? 1 : 0, privacy: .public)")
        let carrier = installReturnSurface(in: source)
        carrier.view.alpha = 0
        transition.animate(alongsideTransition: { _ in
            carrier.view.alpha = 1
        }, completion: { [weak self] context in
            Self.events.notice("END cancelled=\(context.isCancelled ? 1 : 0, privacy: .public)")
            // UIKit reverses this same opacity on an interactive cancellation.
            // Reading content and its WebView have never been replaced.
            self?.removeReturnSurface()
        })
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        removeReturnSurface()
    }

    @discardableResult
    func installReturnSurface(in source: UIViewController) -> UIHostingController<AnyView> {
        if let returnHost { return returnHost }
        let host = UIHostingController(rootView: makeReturnSurface())
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        host.view.accessibilityElementsHidden = true
        source.addChild(host)
        host.view.frame = source.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        source.view.addSubview(host.view)
        host.didMove(toParent: source)
        host.view.layoutIfNeeded()
        returnHost = host
        return host
    }

    func removeReturnSurface() {
        guard let host = returnHost else { return }
        returnHost = nil
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
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
