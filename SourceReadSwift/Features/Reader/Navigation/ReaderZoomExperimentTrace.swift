#if DEBUG
import UIKit

/// Observes public UIKit events without replacing gesture delegates or adding recognizers.
@MainActor
final class ReaderZoomExperimentTrace: NSObject {
    weak var page: UIViewController?
    weak var navigation: UINavigationController?
    weak var webPan: UIPanGestureRecognizer?
    var condition = "A"
    var isReady = false
    private(set) var isArmed = false
    private var isTouching = false
    private var didEndTouch = false
    private var stableFrames = 0
    private var baseline = CGRect.zero
    private var maximumMovement: CGFloat = 0
    private var acceptedZoomStarts = 0
    private var zoomDecisions = 0
    private var acceptedPreflights = 0
    private var sawInteractiveCoordinator = false
    private var lastPercent = -1
    private var completionCancelled: Bool?
    private var events: [[String: Any]] = []
    private var gestures: [UIGestureRecognizer] = []
    private var states: [ObjectIdentifier: Int] = [:]
    private var displayLink: CADisplayLink?
    private var started = CACurrentMediaTime()
    private var outcome = "notArmed"
    private var wasTruncated = false
    private var expectedTouches = 0

    var summary: String {
        let value: [String: Any] = [
            "condition": condition, "ready": isReady, "armed": isArmed,
            "outcome": outcome, "expectedTouches": expectedTouches,
            "acceptedZoomStarts": acceptedZoomStarts, "maximumMovement": maximumMovement,
            "zoomDecisions": zoomDecisions, "acceptedPreflights": acceptedPreflights,
            "interactiveCoordinator": sawInteractiveCoordinator,
            "completionCancelled": completionCancelled as Any? ?? NSNull(),
            "navigation": navigation.map { String(describing: ObjectIdentifier($0)) } ?? "missing",
            "pageSize": [baseline.width, baseline.height], "truncated": wasTruncated,
            "systemShouldBegin": "not publicly observable; original delegates retained",
            "failureDependencies": "only application-installed edges are reported; UIKit internal graph unavailable",
            "events": events
        ]
        guard JSONSerialization.isValidJSONObject(value),
              let bytes = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: bytes, encoding: .utf8) else { return "{\"encodingFailed\":true}" }
        return text
    }

    func reset(condition: String) {
        stop()
        self.condition = condition
        isReady = false
        isArmed = false
        isTouching = false
        didEndTouch = false
        stableFrames = 0
        maximumMovement = 0
        acceptedZoomStarts = 0
        zoomDecisions = 0
        acceptedPreflights = 0
        sawInteractiveCoordinator = false
        lastPercent = -1
        completionCancelled = nil
        expectedTouches = 0
        events = []
        states = [:]
        outcome = "notArmed"
        wasTruncated = false
        started = CACurrentMediaTime()
    }

    func arm() {
        guard isReady, let navigation else { return }
        baseline = presentationFrame()
        isArmed = true
        outcome = "pending"
        var pending = [navigation.view!]
        while let view = pending.popLast() {
            for gesture in view.gestureRecognizers ?? [] where !gestures.contains(where: { $0 === gesture }) {
                gestures.append(gesture)
                gesture.addTarget(self, action: #selector(observeGesture(_:)))
                record("recognizer", ["id": identity(gesture), "class": String(describing: type(of: gesture)),
                    "host": String(describing: type(of: view)), "enabled": gesture.isEnabled,
                    "delegate": gesture.delegate.map { String(describing: type(of: $0)) } ?? "nil",
                    "role": gesture === webPan ? "webPan" : "other"])
            }
            pending.append(contentsOf: view.subviews)
        }
        if let web = page?.view.subviews.compactMap({ $0 as? ReaderEdgeReturnWebView }).first {
            record("appFailureDependency", ["waiting": identity(web.scrollView.panGestureRecognizer),
                "requiredFailure": web.prioritizedEdgeReturn.map(identity) ?? "none",
                "panEnabled": web.scrollView.panGestureRecognizer.isEnabled])
        }
        record("armed", ["width": baseline.width, "height": baseline.height])
        record("publicReturnRecognizers", [
            "edge": navigation.interactivePopGestureRecognizer.map(identity) ?? "none"
        ])
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            record("publicContentReturnRecognizer", [
                "id": navigation.interactiveContentPopGestureRecognizer.map(identity) ?? "none"
            ])
        }
        #endif
        let link = CADisplayLink(target: self, selector: #selector(sampleFrame))
        displayLink = link
        link.add(to: .main, forMode: .common)
        sampleStates()
    }

    func record(_ event: String, _ fields: [String: Any] = [:]) {
        guard events.count < 1400 else { wasTruncated = true; return }
        var entry = fields
        entry["event"] = event
        entry["ms"] = Int((CACurrentMediaTime() - started) * 1000)
        events.append(entry)
    }

    func zoomDecision(location: CGPoint, velocity: CGVector, willBegin: Bool, accepted: Bool) {
        zoomDecisions += 1
        if willBegin && accepted { acceptedZoomStarts += 1 }
        if !willBegin && accepted { acceptedPreflights += 1 }
        record("zoomDecision", ["x": location.x, "y": location.y, "vx": velocity.dx, "vy": velocity.dy,
                                "willBegin": willBegin, "accepted": accepted])
    }

    func transitionCompleted(cancelled: Bool) {
        completionCancelled = cancelled
        record("transitionCompletion", ["cancelled": cancelled])
    }

    func receive(_ event: UIEvent, afterDispatch: Bool) {
        guard isArmed else { return }
        for touch in event.allTouches ?? [] {
            guard let window = touch.window else { continue }
            let point = touch.location(in: window)
            if !afterDispatch && touch.phase == .began && point.x <= 44 {
                isTouching = true
                let hit = touch.view
                let expected = page.map { owner in hit.map { $0 === owner.view || $0.isDescendant(of: owner.view) } ?? false } ?? false
                if expected { expectedTouches += 1 }
                record("touchBegan", ["x": point.x, "y": point.y, "expectedView": expected,
                    "eventTimestamp": touch.timestamp,
                    "hit": hit.map { String(describing: type(of: $0)) } ?? "nil"])
            }
            guard isTouching else { continue }
            if !afterDispatch && touch.phase == .moved {
                record("touchMoved", ["x": point.x, "y": point.y, "eventTimestamp": touch.timestamp])
            }
            sampleStates()
            if afterDispatch && (touch.phase == .ended || touch.phase == .cancelled) {
                record("touchEnded", ["x": point.x, "y": point.y, "eventTimestamp": touch.timestamp,
                                      "cancelled": touch.phase == .cancelled])
                isTouching = false
                didEndTouch = true
            }
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        for gesture in gestures { gesture.removeTarget(self, action: #selector(observeGesture(_:))) }
        gestures = []
    }

    private func identity(_ gesture: UIGestureRecognizer) -> String { String(describing: ObjectIdentifier(gesture)) }

    @objc private func observeGesture(_ gesture: UIGestureRecognizer) {
        record("recognizerAction", ["id": identity(gesture), "state": gesture.state.rawValue])
    }

    private func sampleStates() {
        for gesture in gestures {
            let key = ObjectIdentifier(gesture)
            let state = gesture.state.rawValue
            guard states[key] != state else { continue }
            states[key] = state
            record("recognizerState", ["id": identity(gesture), "state": state])
        }
    }

    private func presentationFrame() -> CGRect {
        guard let page, let window = page.view.window else { return .zero }
        let layer = page.view.layer.presentation() ?? page.view.layer
        return layer.convert(layer.bounds, to: window.layer.presentation() ?? window.layer)
    }

    @objc private func sampleFrame() {
        sampleStates()
        let frame = presentationFrame()
        let movement = max(abs(frame.minX - baseline.minX), abs(frame.width - baseline.width))
        if movement > maximumMovement + 0.5 {
            maximumMovement = movement
            record("pageMovement", ["x": frame.minX, "width": frame.width, "maximum": movement])
        }
        let coordinator = navigation?.transitionCoordinator
        if coordinator?.isInteractive == true && !sawInteractiveCoordinator {
            sawInteractiveCoordinator = true
            record("interactiveCoordinator", ["percent": coordinator!.percentComplete])
        }
        if let coordinator, coordinator.isInteractive {
            let percent = Int(coordinator.percentComplete * 100)
            if percent != lastPercent {
                lastPercent = percent
                record("interactiveProgress", ["percent": percent, "cancelled": coordinator.isCancelled])
            }
        }
        guard didEndTouch else { return }
        let isAtRoot = navigation?.topViewController !== page
        let restored = movement < 0.5 && coordinator == nil
        stableFrames = restored || (isAtRoot && coordinator == nil) ? stableFrames + 1 : 0
        guard stableFrames >= 3 else { return }
        if isAtRoot { outcome = "completed" }
        else if completionCancelled == true { outcome = "cancelled" }
        else if acceptedZoomStarts > 0 && maximumMovement > 0.5 { outcome = "zoomMovedThenRestored" }
        else if acceptedZoomStarts > 0 { outcome = "zoomAcceptedWithoutObservedMovement" }
        else if zoomDecisions == 0 { outcome = "notStartedNoZoomDecision" }
        else if acceptedPreflights > 0 { outcome = "preflightAcceptedWithoutBegin" }
        else { outcome = "appRejectedZoom" }
        record("settled", ["outcome": outcome])
        isArmed = false
        stop()
    }
}

/// The original event continues to UIKit exactly once; observations never consume it.
@MainActor
final class ReaderZoomExperimentWindow: UIWindow {
    weak var trace: ReaderZoomExperimentTrace?
    override func sendEvent(_ event: UIEvent) {
        trace?.receive(event, afterDispatch: false)
        super.sendEvent(event)
        trace?.receive(event, afterDispatch: true)
    }
}
#endif
