import SwiftUI
import UIKit

/// All reader entry points share a native presentation transaction, including entries in sheets.
@MainActor
final class ReaderNavigationRouter: NSObject, UINavigationControllerDelegate, UIAdaptivePresentationControllerDelegate,
                                    UIGestureRecognizerDelegate {
    private weak var navigation: ReaderNavigationController?
    private weak var appState: AppState?
    private var request: ReaderDestinationRequest?
    /// The request whose view tree is actually mounted. A parked reader is
    /// re-presented with its original content, while `request` only supplies
    /// the current owner's return callback.
    private var mountedRequest: ReaderDestinationRequest?
    private(set) var reader: NativeReaderHostingController?
    private var isModal = false
    private var compatibility: ReaderCompatibilityTransition?
    private var nativePopWasEnabled: Bool?
    private var stackPopState: StackPopState?
    private var environment = ReaderHostingEnvironment(values: EnvironmentValues())

    private struct StackPopState {
        let edgeWasEnabled: Bool
        weak var edgeDelegate: UIGestureRecognizerDelegate?
        let contentWasEnabled: Bool?
    }

    /// A returned reader keeps its live WebView for exactly one book. Reopening
    /// that book must not reload the shell, re-lay-out the document or re-resolve
    /// the restored paragraph, so the hosting controller is parked instead of
    /// committed. Everything else releases it immediately.
    private struct DormantReader {
        let controller: NativeReaderHostingController
        var request: ReaderDestinationRequest
        let sourceID: String?
        /// Must still match on reuse. A WebKit process killed while parked
        /// reloads its shell; that parked document is no longer reusable.
        let shellLoads: Int
    }
    private var dormant: DormantReader?

    func attach(_ navigation: ReaderNavigationController, appState: AppState) {
        self.navigation = navigation
        self.appState = appState
        navigation.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(releaseDormantReader),
            name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }

    /// Only one parked reader is kept; a memory warning must hand its WebView back.
    @objc private func releaseDormantReader() { releaseDormant() }

    private func releaseDormant() {
        guard let parked = dormant else { return }
        dormant = nil
        // Stay hidden: this controller is being released, and re-inserting it
        // into the accessibility tree would let a dead reader answer queries.
        parked.controller.session.commitExit()
        NavigationTrace.shared.mark("reader-session", "release dormant \(parked.controller.session.id.uuidString.prefix(8))")
    }

    var hasDormantReader: Bool { dormant != nil }

    func updateEnvironment(_ environment: EnvironmentValues) {
        let snapshot = ReaderHostingEnvironment(values: environment)
        guard self.environment != snapshot else { return }
        self.environment = snapshot
        refreshReaderEnvironment()
    }

    @discardableResult
    func open(_ request: ReaderDestinationRequest) -> Bool {
        guard reader == nil, let navigation, let appState else { return false }
        self.request = request
        // Same book, same cover source: the parked controller still owns a live
        // document at the exact paragraph the reader left, so re-present it.
        let session: ReaderNavigationSession
        let controller: NativeReaderHostingController
        var isReused = false
        if let parked = dormant, parked.request.book.id == request.book.id,
           parked.sourceID == request.sourceID,
           parked.request.requestedChapterIndex == request.requestedChapterIndex,
           parked.controller.session.phase != .closed,
           parked.controller.session.isContentReady,
           parked.controller.session.shellLoads == parked.shellLoads {
            dormant = nil
            isReused = true
            session = parked.controller.session
            controller = parked.controller
            mountedRequest = parked.request
            session.recordBridgeEvent("reopen:dormant")
            NavigationTrace.shared.mark("reader-session", "reuse \(session.id.uuidString.prefix(8))")
        } else {
            releaseDormant()
            session = ReaderNavigationSession(bookID: request.book.id)
            controller = NativeReaderHostingController.make(request: request, session: session,
                appState: appState, environment: environment, close: { [weak self] in self?.close() })
            mountedRequest = request
        }
        reader = controller
        session.readNativeConfiguration = { [weak controller, weak navigation] in
            guard let controller else { return "closed" }
            let presented = controller.presentedViewController.map { String(describing: type(of: $0)) } ?? "none"
            let transition: String
            if #available(iOS 18.0, *) { transition = String(describing: controller.preferredTransition) }
            else { transition = "compatibility" }
            return "top=\(navigation?.topViewController === controller);presented=\(presented);preferred=\(transition)"
        }
        controller.onClosed = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.finish(controller)
        }
        controller.view.backgroundColor = .systemBackground
        controller.modalPresentationCapturesStatusBarAppearance = true
        appState.isReaderPresented = true
        // A fresh session enters .reading from its own viewDidAppear; only a
        // parked one has to be restored before the push begins.
        if isReused {
            controller.prepareForRepresentation()
        }
        let presenter = presentedController(in: navigation)
        isModal = presenter != nil
        configureTransition(controller, sourceID: request.sourceID)

        if let presenter {
            controller.modalPresentationStyle = .fullScreen
            if let compatibility {
                controller.transitioningDelegate = compatibility
                controller.modalPresentationStyle = .custom
            }
            compatibility?.attach(to: controller.view,
                                  beginReturn: { [weak self] in self?.close() })
            presenter.present(controller, animated: !UIAccessibility.isReduceMotionEnabled)
            controller.presentationController?.delegate = self
        } else {
            if compatibility != nil { prepareStackPop(in: navigation) }
            navigation.pushViewController(controller, animated: !UIAccessibility.isReduceMotionEnabled)
        }
        NavigationTrace.shared.mark("reader-session", "open \(session.id.uuidString.prefix(8)) modal=\(isModal)")
        return true
    }

    func close() {
        guard let reader, reader.session.phase != .closed else { return }
        reader.session.recordBridgeEvent("close:modal=\(isModal);stack=\(navigation?.viewControllers.count ?? 0)")
        // Native zoom supports interrupting its opening transition. Keep the request alive until completion.
        reader.session.willLeave()
        let animated = compatibility?.shouldAnimateReturn ?? !UIAccessibility.isReduceMotionEnabled
        if isModal {
            reader.dismiss(animated: animated) { [weak self, weak reader] in
                guard let reader else { return }
                if reader.presentingViewController == nil { self?.finish(reader) }
                else { reader.session.didAppear() }
            }
        } else if let navigation {
            if let coordinator = navigation.transitionCoordinator {
                coordinator.animate(alongsideTransition: nil) { [weak self, weak navigation, weak reader] _ in
                    guard let self, let navigation, let reader, self.reader === reader,
                          navigation.topViewController === reader else { return }
                    self.performPop(reader, in: navigation, animated: animated)
                }
            } else {
                performPop(reader, in: navigation, animated: animated)
            }
        }
    }

    private func performPop(_ reader: NativeReaderHostingController, in navigation: ReaderNavigationController, animated: Bool) {
        reader.session.willLeave()
        navigation.popViewController(animated: animated)
        if navigation.topViewController === reader, navigation.transitionCoordinator == nil {
            navigation.popViewController(animated: false)
            if !navigation.viewControllers.contains(reader) {
                finish(reader)
            }
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
        if #available(iOS 18.0, *),
           ProcessInfo.processInfo.arguments.contains("--reader-zoom-isolation"),
           let liveSource = ReaderZoomSources.shared.source(id: sourceID, window: navigation.view.window) {
            let options = UIViewController.Transition.ZoomOptions()
            options.interactiveDismissShouldBegin = { [weak controller] context in
                guard let controller else { return false }
                let blocker = controller.presentedViewController.map { String(describing: type(of: $0)) } ?? "none"
                let accepted = controller.session.allowsReturn
                    && controller.presentedViewController == nil
                    && context.location.x <= ReaderEdgeTapPolicy.reservedLeadingWidth
                controller.session.recordZoomDecision(location: context.location, willBegin: context.willBegin,
                                                       accepted: accepted, blocker: blocker)
                return accepted
            }
            controller.session.recordZoomSource(liveSource)
            controller.preferredTransition = .zoom(options: options) { [weak navigation, weak controller] _ in
                let source = ReaderZoomSources.shared.source(id: sourceID, window: navigation?.view.window)
                controller?.session.recordZoomSource(source)
                return source
            }
        } else {
            if let liveSource = ReaderZoomSources.shared.source(id: sourceID, window: navigation.view.window) {
                controller.session.recordZoomSource(liveSource)
            }
            if isModal {
                nativePopWasEnabled = navigation.interactivePopGestureRecognizer?.isEnabled
                navigation.interactivePopGestureRecognizer?.isEnabled = false
            }
            compatibility = ReaderCompatibilityTransition(session: controller.session,
                source: { [weak navigation, weak controller] in
                    let resolved = ReaderZoomSources.shared.source(id: sourceID, window: navigation?.view.window)
                    controller?.session.recordZoomSource(resolved)
                    return resolved
                })
        }
    }

    private func prepareStackPop(in navigation: ReaderNavigationController) {
        guard let edge = navigation.interactivePopGestureRecognizer else { return }
        stackPopState = StackPopState(edgeWasEnabled: edge.isEnabled, edgeDelegate: edge.delegate,
                                      contentWasEnabled: contentPop(in: navigation)?.isEnabled)
        enableStackPop(in: navigation)
    }

    private func enableStackPop(in navigation: UINavigationController) {
        guard stackPopState != nil, let edge = navigation.interactivePopGestureRecognizer else { return }
        // The outer stack hides its bar. Keep UIKit's edge recognizer and animator,
        // but apply the reader's return gate instead of the bar's gate.
        if edge.delegate !== self { edge.delegate = self }
        if !edge.isEnabled { edge.isEnabled = true }
        // The iOS 26 full-content gesture competes with horizontal page turns.
        if let content = contentPop(in: navigation), content.isEnabled { content.isEnabled = false }
    }

    private func restoreStackPop() {
        guard let state = stackPopState else { return }
        stackPopState = nil
        guard let navigation else { return }
        if let edge = navigation.interactivePopGestureRecognizer {
            edge.delegate = state.edgeDelegate
            if edge.isEnabled != state.edgeWasEnabled { edge.isEnabled = state.edgeWasEnabled }
        }
        if let wasEnabled = state.contentWasEnabled, let content = contentPop(in: navigation),
           content.isEnabled != wasEnabled {
            content.isEnabled = wasEnabled
        }
    }

    private func contentPop(in navigation: UINavigationController) -> UIGestureRecognizer? {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return navigation.interactiveContentPopGestureRecognizer }
        #endif
        return nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let surface = gestureRecognizer.view else { return false }
        let x = touch.location(in: surface).x
        let distance = surface.effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? surface.bounds.maxX - x : x - surface.bounds.minX
        // Keep a leading-edge start even when UIKit implements the recognizer as a pan.
        return distance >= 0 && distance <= ReaderEdgeTapPolicy.reservedLeadingWidth
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard stackPopState != nil, let navigation, let reader,
              gestureRecognizer === navigation.interactivePopGestureRecognizer,
              navigation.viewControllers.count > 1, navigation.topViewController === reader,
              navigation.transitionCoordinator == nil, navigation.presentedViewController == nil,
              reader.presentedViewController == nil else { return false }
        guard reader.session.phase == .reading, reader.session.allowsReturn else { return false }
        if let pan = gestureRecognizer as? UIPanGestureRecognizer, pan.numberOfTouches > 0 {
            let translation = pan.translation(in: navigation.view)
            let movement = translation == .zero ? pan.velocity(in: navigation.view) : translation
            let trailing = navigation.view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? -movement.x : movement.x
            if movement != .zero { return trailing > abs(movement.y) }
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === navigation?.interactivePopGestureRecognizer,
              otherGestureRecognizer !== gestureRecognizer, otherGestureRecognizer is UIPanGestureRecognizer,
              let readerView = reader?.viewIfLoaded, let otherView = otherGestureRecognizer.view else { return false }
        return otherView.isDescendant(of: readerView)
    }

    private func finish(_ controller: NativeReaderHostingController) {
        guard reader === controller else { return }
        compatibility?.detach()
        compatibility = nil
        restoreStackPop()
        if let nativePopWasEnabled { navigation?.interactivePopGestureRecognizer?.isEnabled = nativePopWasEnabled }
        nativePopWasEnabled = nil
        let returning = request
        reader = nil
        request = nil
        mountedRequest = nil
        // Parking is only safe when the document really rendered: an unpositioned
        // or errored reader must still run its committed exit and release the view.
        if let returning, isReusable(controller) {
            releaseDormant()
            controller.session.parkForReuse()
            controller.setParked(true)
            dormant = DormantReader(controller: controller, request: returning, sourceID: returning.sourceID,
                shellLoads: controller.session.shellLoads)
            controller.session.recordBridgeEvent("dormant")
            NavigationTrace.shared.mark("reader-session", "park \(controller.session.id.uuidString.prefix(8))")
        } else {
            // Cleanup captures the last position before releasing the sole owner of the live reader.
            controller.session.commitExit()
        }
        appState?.isReaderPresented = false
        if let onReturn = returning?.onReturn, var parked = dormant {
            // The live view tree is kept; its owner only needs the new return hook.
            parked.request.onReturn = onReturn
            dormant = parked
        }
        returning?.onReturn()
    }

    /// Proof the parked session can be shown again without a fake ready state:
    /// one live WebView, a rendered document and a non-closed session.
    private func isReusable(_ controller: NativeReaderHostingController) -> Bool {
        let session = controller.session
        return session.canPark
            && session.phase != .closed
            && session.isContentReady
            && session.hasPresentedContent
            && session.webViewIdentities.count == 1
            && controller.presentedViewController == nil
    }

    private func refreshReaderEnvironment() {
        guard let reader, let request = mountedRequest, let appState else { return }
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
            enableStackPop(in: navigationController)
        } else {
            finish(reader)
        }
        compatibility?.didSettle()
    }

    func navigationController(_ navigationController: UINavigationController,
                              animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard operation == .push, toVC === reader else { return nil }
        return compatibility?.animator(isOpening: true)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        if let reader, presentationController.presentedViewController === reader { finish(reader) }
    }
}
