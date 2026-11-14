import SwiftUI
import UIKit
import OSLog

/// Observes UIKit's existing pop and adds a carrier only on routes without the desk zoom.
final class ReaderBookPassageController: UIViewController {
    private static let events = Logger(subsystem: "com.edc21.SourceReadSwift.book-passage", category: "return")
    var onArrival: () -> Void = {}
    var onInteractivePop: () -> Void = {}
    var onInteractivePopEnd: (_ isCancelled: Bool) -> Void = { _ in }
    var usesNativeDeskReturn = false
    var canPrepareReturn = false {
        didSet {
            guard canPrepareReturn != oldValue, isViewLoaded else { return }
            // Removing the opening overlay need not relayout the UIKit probe.
            if canPrepareReturn { attachGestureEvidence() } else { detachGestureEvidence() }
        }
    }
    var makeReturnSurface: () -> AnyView = { AnyView(EmptyView()) }
    private(set) var returnHost: UIHostingController<AnyView>?
    #if DEBUG
    private var observedGestures: [UIGestureRecognizer] = []
    private var activeGestures = Set<ObjectIdentifier>()
    private var movedGestures = Set<ObjectIdentifier>()
    private var nativeMotionCount = 0
    #endif

    override func loadView() {
        #if DEBUG
        let evidence = NativeBookGestureEvidenceView()
        evidence.readGestureState = { [weak self] in
            guard let self else { return "detached" }
            let edgeEnabled = self.navigationController?.interactivePopGestureRecognizer?.isEnabled ?? false
            return "ready=\(self.canPrepareReturn),zoom=\(self.usesNativeDeskReturn),edge=\(edgeEnabled);"
                + NativeBookGestureProbe.describe(self.observedGestures)
                + ";" + NativeBookGestureProbe.describeWebPans(in: self.navigationController?.topViewController?.view)
        }
        view = evidence
        #else
        view = UIView()
        #endif
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        #if DEBUG
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "reader.nativeBookGestureEvidence"
        view.accessibilityValue = "0"
        #endif
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        removeReturnSurface()
        attachGestureEvidence()
        DispatchQueue.main.async { [weak self] in self?.onArrival() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        attachGestureEvidence()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard canPrepareReturn, let transition = transitionCoordinator,
              let source = transition.viewController(forKey: .from), belongs(to: source),
              let navigation = source.navigationController ?? navigationController,
              ReaderNativePopPolicy.isPop(from: source, to: transition.viewController(forKey: .to),
                in: navigation, isInteractive: transition.isInteractive) else { return }
        Self.events.notice("BEGIN interactive=\(transition.isInteractive ? 1 : 0, privacy: .public)")
        if transition.isInteractive {
            onInteractivePop()
            let onEnd = onInteractivePopEnd
            transition.notifyWhenInteractionChanges { context in
                let percent = Int((context.percentComplete * 100).rounded())
                Self.events.notice("RELEASE cancelled=\(context.isCancelled ? 1 : 0, privacy: .public) percent=\(percent, privacy: .public)")
                onEnd(context.isCancelled)
            }
        }
        if usesNativeDeskReturn || String(describing: type(of: source)).contains("UIHostingController") {
            // The system already owns both surfaces. A second opaque paper
            // sheet here becomes a white card over the actual book landing.
            Self.events.notice("SURFACE system-book")
            transition.animate(alongsideTransition: nil) { context in
                Self.events.notice("END cancelled=\(context.isCancelled ? 1 : 0, privacy: .public)")
            }
            return
        }
        let carrier = installReturnSurface(in: source)
        carrier.view.alpha = 0
        transition.animate(alongsideTransition: { _ in
            carrier.view.alpha = 1
        }, completion: { [weak self] context in
            Self.events.notice("END cancelled=\(context.isCancelled ? 1 : 0, privacy: .public)")
            // UIKit reverses this same opacity on an interactive cancellation.
            // Reading content and its WebView have never been replaced.
            self?.finishReturnSurface(carrier)
        })
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        removeReturnSurface()
        detachGestureEvidence()
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

    func finishReturnSurface(_ carrier: UIHostingController<AnyView>) {
        guard returnHost === carrier else { return }
        removeReturnSurface()
    }

    func removeReturnSurface() {
        guard let host = returnHost else { return }
        returnHost = nil
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
    }

    private func attachGestureEvidence() {
        #if DEBUG
        guard canPrepareReturn, let navigation = navigationController,
              let source = navigation.topViewController, belongs(to: source),
              let navigationView = navigation.view, let sourceView = source.view else { return }
        // Zoom can cancel before a pop is committed, without appearance callbacks.
        // Observe existing native recognizers; never replace their delegate/driver.
        var candidates = NativeBookGestureProbe.collect(in: navigationView)
        candidates.append(contentsOf: NativeBookGestureProbe.collect(in: sourceView))
        if let edge = navigation.interactivePopGestureRecognizer { candidates.append(edge) }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), let content = navigation.interactiveContentPopGestureRecognizer {
            candidates.append(content)
        }
        #endif
        let previousCount = observedGestures.count
        for gesture in candidates {
            guard !(gesture is UITapGestureRecognizer), !(gesture is UILongPressGestureRecognizer),
                  !observedGestures.contains(where: { $0 === gesture }) else { continue }
            gesture.addTarget(self, action: #selector(observeNativeMotion(_:)))
            observedGestures.append(gesture)
        }
        if previousCount != observedGestures.count {
            Self.events.notice("OBSERVERS attached=\(self.observedGestures.count, privacy: .public)")
        }
        #endif
    }

    func detachGestureEvidence() {
        #if DEBUG
        for gesture in observedGestures {
            gesture.removeTarget(self, action: #selector(observeNativeMotion(_:)))
        }
        observedGestures.removeAll()
        activeGestures.removeAll()
        movedGestures.removeAll()
        #endif
    }

    #if DEBUG
    @objc private func observeNativeMotion(_ gesture: UIGestureRecognizer) {
        let identity = ObjectIdentifier(gesture)
        switch gesture.state {
        case .began:
            activeGestures.insert(identity)
            if movedGestures.insert(identity).inserted {
                nativeMotionCount += 1
                view.accessibilityValue = String(nativeMotionCount)
                Self.events.notice("PAN_MOVED began native=1 count=\(self.nativeMotionCount, privacy: .public)")
            }
        case .changed:
            if movedGestures.insert(identity).inserted {
                nativeMotionCount += 1
                view.accessibilityValue = String(nativeMotionCount)
                Self.events.notice("PAN_MOVED changed native=1 count=\(self.nativeMotionCount, privacy: .public)")
            }
        case .ended, .cancelled, .failed:
            activeGestures.remove(identity)
            movedGestures.remove(identity)
        default: break
        }
    }
    #endif

    private func belongs(to controller: UIViewController) -> Bool {
        var ancestor: UIViewController? = self
        while let candidate = ancestor {
            if candidate === controller { return true }
            ancestor = candidate.parent
        }
        return false
    }
}
