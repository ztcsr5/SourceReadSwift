import SwiftUI
import UIKit

/// All reader entry points share a native presentation transaction, including entries in sheets.
@MainActor
final class ReaderNavigationRouter: NSObject, UINavigationControllerDelegate, UIAdaptivePresentationControllerDelegate {
    private weak var navigation: ReaderNavigationController?
    private weak var appState: AppState?
    private var request: ReaderDestinationRequest?
    private(set) var reader: NativeReaderHostingController?
    private var isModal = false
    private var compatibility: ReaderCompatibilityTransition?
    private var nativePopWasEnabled: Bool?
    private var environment = EnvironmentValues()

    func attach(_ navigation: ReaderNavigationController, appState: AppState) {
        self.navigation = navigation
        self.appState = appState
        navigation.delegate = self
    }

    func updateEnvironment(_ environment: EnvironmentValues) {
        self.environment = environment
        refreshReaderEnvironment()
    }

    @discardableResult
    func open(_ request: ReaderDestinationRequest) -> Bool {
        guard reader == nil, let navigation, let appState else { return false }
        self.request = request
        let session = ReaderNavigationSession(bookID: request.book.id)
        let controller = NativeReaderHostingController.make(request: request, session: session,
            appState: appState, environment: environment, close: { [weak self] in self?.close() })
        reader = controller
        controller.onClosed = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.finish(controller)
        }
        controller.view.backgroundColor = .systemBackground
        controller.modalPresentationCapturesStatusBarAppearance = true
        appState.isReaderPresented = true
        configureTransition(controller, sourceID: request.sourceID)

        if let presenter = presentedController(in: navigation) {
            isModal = true
            controller.modalPresentationStyle = .fullScreen
            if let compatibility {
                controller.transitioningDelegate = compatibility
                controller.modalPresentationStyle = .custom
            }
            presenter.present(controller, animated: !UIAccessibility.isReduceMotionEnabled)
            controller.presentationController?.delegate = self
        } else {
            isModal = false
            navigation.pushViewController(controller, animated: !UIAccessibility.isReduceMotionEnabled)
        }
        compatibility?.attach(to: isModal ? controller.view : navigation.view,
                              beginReturn: { [weak self] in self?.close() })
        NavigationTrace.shared.mark("reader-session", "open \(session.id.uuidString.prefix(8)) modal=\(isModal)")
        return true
    }

    func close() {
        guard let reader, reader.session.phase != .closed else { return }
        // Native zoom supports interrupting its opening transition. Keep the request alive until completion.
        reader.session.willLeave()
        if isModal {
            reader.dismiss(animated: !UIAccessibility.isReduceMotionEnabled) { [weak self, weak reader] in
                guard let reader else { return }
                if reader.presentingViewController == nil { self?.finish(reader) }
                else { reader.session.didAppear() }
            }
        } else {
            navigation?.popViewController(animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }

    /// Details presented by a reader select within that session instead of opening a second WebView.
    @discardableResult
    func returnToReader(bookID: String, chapterIndex: Int) -> Bool {
        guard let reader, reader.session.bookID == bookID, reader.session.phase != .closed else { return false }
        let select = { [weak reader] in _ = reader?.session.selectChapter(chapterIndex) }
        if reader.presentedViewController != nil { reader.dismiss(animated: true, completion: select) }
        else { select() }
        return true
    }

    private func configureTransition(_ controller: NativeReaderHostingController, sourceID: String?) {
        guard let navigation else { return }
        if #available(iOS 18.0, *) {
            let options = UIViewController.Transition.ZoomOptions()
            options.interactiveDismissShouldBegin = { [weak controller] context in
                guard let controller, controller.presentedViewController == nil else { return false }
                return controller.session.allowsReturn
                    && context.location.x <= ReaderEdgeTapPolicy.reservedLeadingWidth
            }
            controller.preferredTransition = .zoom(options: options) { [weak navigation] _ in
                ReaderZoomSources.shared.source(id: sourceID, window: navigation?.view.window)
            }
        } else {
            nativePopWasEnabled = navigation.interactivePopGestureRecognizer?.isEnabled
            navigation.interactivePopGestureRecognizer?.isEnabled = false
            compatibility = ReaderCompatibilityTransition(session: controller.session,
                source: { [weak navigation] in
                    ReaderZoomSources.shared.source(id: sourceID, window: navigation?.view.window)
                })
        }
    }

    private func finish(_ controller: NativeReaderHostingController) {
        guard reader === controller else { return }
        // Cleanup captures the last position before releasing the sole owner of the live reader.
        controller.session.commitExit()
        let onReturn = request?.onReturn
        compatibility?.detach()
        compatibility = nil
        if let nativePopWasEnabled { navigation?.interactivePopGestureRecognizer?.isEnabled = nativePopWasEnabled }
        nativePopWasEnabled = nil
        reader = nil
        request = nil
        appState?.isReaderPresented = false
        onReturn?()
    }

    private func refreshReaderEnvironment() {
        guard let reader, let request, let appState else { return }
        reader.rootView = NativeReaderHostingController.content(request: request, session: reader.session,
            appState: appState, environment: environment, close: { [weak self] in self?.close() })
    }

    private func presentedController(in controller: UIViewController) -> UIViewController? {
        if let presented = controller.presentedViewController, !presented.isBeingDismissed {
            return presentedController(in: presented) ?? presented
        }
        for child in controller.children.reversed() {
            if let presented = presentedController(in: child) { return presented }
        }
        return nil
    }

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController,
                              animated: Bool) {
        guard let reader, !isModal else { return }
        if viewController !== reader { reader.session.willLeave() }
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController,
                              animated: Bool) {
        guard let reader, !isModal else { return }
        if navigationController.viewControllers.contains(where: { $0 === reader }) {
            reader.session.didAppear()
        } else {
            finish(reader)
        }
        compatibility?.didSettle()
    }

    func navigationController(_ navigationController: UINavigationController,
                              animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        compatibility?.animator(isOpening: operation == .push)
    }

    func navigationController(_ navigationController: UINavigationController,
                              interactionControllerFor animationController: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        compatibility?.interaction
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        if let reader, presentationController.presentedViewController === reader { finish(reader) }
    }
}
