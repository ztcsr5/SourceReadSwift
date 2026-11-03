import UIKit

/// One finite durability lease. Completion and expiration both end it idempotently.
@MainActor
final class ReadingWriteBackgroundLease {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var didExpire = false

    init() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "ReadingProgressFlush") { [weak self] in
            // UIKit invokes expiration synchronously on main; release before returning.
            self?.didExpire = true
            self?.end()
        }
        if didExpire { end() }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
