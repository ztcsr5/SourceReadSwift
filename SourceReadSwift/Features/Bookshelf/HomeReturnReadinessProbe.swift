#if DEBUG
import SwiftUI
import UIKit

/// Measures interactive return inside the app, excluding remote XCTest query latency.
struct HomeReturnReadinessProbe: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> HomeReturnReadinessController {
        HomeReturnReadinessController()
    }

    func updateUIViewController(_ controller: HomeReturnReadinessController, context: Context) {}
}

final class HomeReturnReadinessController: UIViewController {
    private var releasedAt: TimeInterval?
    private var samplingTask: Task<Void, Never>?

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "bookshelf.returnReadiness"
        view.accessibilityValue = "idle"
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let transition = transitionCoordinator, transition.isInteractive,
              let destination = transition.viewController(forKey: .to), belongs(to: destination) else { return }
        view.accessibilityValue = "tracking"
        transition.notifyWhenInteractionChanges { [weak self] context in
            guard !context.isCancelled else {
                self?.view.accessibilityValue = "cancelled"
                return
            }
            self?.releasedAt = ProcessInfo.processInfo.systemUptime
        }
        transition.animate(alongsideTransition: nil) { [weak self, weak destination] context in
            guard !context.isCancelled, let destination else { return }
            self?.sampleInputReadiness(in: destination)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        samplingTask?.cancel()
        samplingTask = nil
        releasedAt = nil
        view.accessibilityValue = "idle"
    }

    private func sampleInputReadiness(in destination: UIViewController) {
        guard let releasedAt else {
            view.accessibilityValue = "missing-interaction-timestamp"
            return
        }
        samplingTask?.cancel()
        samplingTask = Task { @MainActor [weak self, weak destination] in
            while !Task.isCancelled, let self, let destination {
                let elapsed = ProcessInfo.processInfo.systemUptime - releasedAt
                if let root = destination.viewIfLoaded, let window = root.window {
                    let point = root.convert(CGPoint(x: root.bounds.midX, y: root.bounds.midY), to: window)
                    let hit = window.hitTest(point, with: nil)
                    if !root.isHidden, root.alpha > 0.99,
                       let hit, hit.isDescendant(of: root), destination.navigationController?.topViewController === destination {
                        self.view.accessibilityValue = String(elapsed)
                        return
                    }
                }
                if elapsed > 5 {
                    self.view.accessibilityValue = "input-timeout"
                    return
                }
                do { try await Task.sleep(nanoseconds: 10_000_000) }
                catch is CancellationError { return }
                catch { self.view.accessibilityValue = "sampling-error"; return }
            }
        }
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
#endif
