import UIKit
import OSLog

/// Configures the destination's public native zoom; no navigation delegate replacement.
@available(iOS 18.0, *)
@MainActor final class NativeBookReturnTransition {
    private static let events = Logger(subsystem: "com.edc21.SourceReadSwift.book-passage", category: "alignment")
    private weak var controller: UIViewController?
    private weak var handoff: ReadingCoverHandoff?
    private weak var anchor: UIView?
    private let sourceID: String
    private var original: UIViewController.Transition?
    private var installed: UIViewController.Transition?
    private var lastAlignment: CGRect?
    private var lastSourceAvailability: Bool?
    private var lastRectAvailability: Bool?
    var allowsInteractiveReturn = false

    init(sourceID: String, handoff: ReadingCoverHandoff) {
        self.sourceID = sourceID
        self.handoff = handoff
    }

    func install(in destination: UIViewController, anchor: UIView) {
        guard let source = handoff?.nativeCover(for: sourceID), !source.bounds.isEmpty,
              let rect = BookReturnGeometry.alignment(of: anchor, in: destination) else { return }
        self.anchor = anchor
        lastAlignment = rect
        if controller === destination, destination.preferredTransition === installed, installed != nil { return }
        guard destination.transitionCoordinator == nil else { return }
        restore()
        controller = destination
        original = destination.preferredTransition
        self.anchor = anchor
        lastAlignment = rect
        let options = UIViewController.Transition.ZoomOptions()
        options.interactiveDismissShouldBegin = { [weak self] _ in
            self?.allowsInteractiveReturn == true
        }
        options.alignmentRectProvider = { [weak self] context in
            guard let self, context.zoomedViewController === self.controller else { return nil }
            if let anchor = self.anchor,
               let measured = BookReturnGeometry.alignment(of: anchor, in: context.zoomedViewController) {
                self.lastAlignment = measured
            }
            let resolved = self.lastAlignment
            let isReady = resolved != nil
            if self.lastRectAvailability != isReady {
                self.lastRectAvailability = isReady
                Self.events.notice("ALIGN_RECT ready=\(isReady ? 1 : 0, privacy: .public)")
            }
            return resolved
        }
        let transition = UIViewController.Transition.zoom(options: options) { [weak self] _ in
            guard let self else { return nil }
            let source = self.handoff?.nativeCover(for: self.sourceID)
            let isReady = source != nil
            if self.lastSourceAvailability != isReady {
                self.lastSourceAvailability = isReady
                Self.events.notice("ALIGN_SOURCE ready=\(isReady ? 1 : 0, privacy: .public)")
            }
            return source
        }
        installed = transition
        destination.preferredTransition = transition
        Self.events.notice("ALIGN_CONFIGURED")
    }

    func restore(prefersDefault: Bool = false) {
        if let controller, controller.preferredTransition === installed, installed != nil {
            controller.preferredTransition = prefersDefault ? nil : original
        }
        installed = nil
        original = nil
        controller = nil
        anchor = nil
        lastAlignment = nil
        lastSourceAvailability = nil
        lastRectAvailability = nil
    }
}
