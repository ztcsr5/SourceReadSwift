import Foundation
import Combine

struct SourceBrowserLoginRequest: Identifiable, Equatable, Sendable {
    static let maximumResponseBytes = 4 * 1024 * 1024
    let id = UUID()
    let url: URL
    let title: String
}

/// Carries one login operation's cancellation across synchronous JavaScript/GCD callouts.
final class SourceLoginCancellation: @unchecked Sendable {
    @TaskLocal static var current: SourceLoginCancellation?
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }
}

/// Keeps a synchronous source login call suspended while its visible browser is open.
@MainActor
final class SourceBrowserLoginCoordinator: ObservableObject {
    static let shared = SourceBrowserLoginCoordinator()
    @Published private(set) var request: SourceBrowserLoginRequest?
    private var completion: ((SourceResponse?) -> Void)?

    /// Returns the visible page after cookie synchronization, or nil on cancellation/timeout.
    nonisolated static func requestSynchronously(url: URL, title: String, timeout: TimeInterval = 180) -> SourceResponse? {
        let cancellation = SourceLoginCancellation.current
        guard !Thread.isMainThread, cancellation?.isCancelled != true,
              SourceLoginBrowserAction.browserPageURL(url.absoluteString) != nil else { return nil }
        let request = SourceBrowserLoginRequest(url: url, title: title)
        let result = BrowserLoginResult()
        let semaphore = DispatchSemaphore(value: 0)
        Task { @MainActor in
            guard !result.isCancelled, cancellation?.isCancelled != true else { return }
            shared.present(request) { response in
                result.finish(response)
                semaphore.signal()
            }
        }
        let deadline = Date().addingTimeInterval(max(0.05, min(timeout, 600)))
        while true {
            if semaphore.wait(timeout: .now() + 0.1) == .success {
                return cancellation?.isCancelled == true ? nil : result.value
            }
            if cancellation?.isCancelled == true || Task.isCancelled || Date() >= deadline {
                result.cancel()
                Task { @MainActor in shared.cancel(id: request.id) }
                return nil
            }
        }
    }

    func present(_ request: SourceBrowserLoginRequest, completion: @escaping (SourceResponse?) -> Void) {
        if self.request != nil { finish(nil) }
        self.completion = completion
        self.request = request
    }

    func submit(id: UUID, response: SourceResponse) {
        guard request?.id == id else { return }
        guard SourceLoginBrowserAction.browserPageURL(response.url.absoluteString) != nil,
              response.data.count <= SourceBrowserLoginRequest.maximumResponseBytes else { finish(nil); return }
        finish(response)
    }

    func cancel(id: UUID) {
        guard request?.id == id else { return }
        finish(nil)
    }

    private func finish(_ value: SourceResponse?) {
        let callback = completion
        completion = nil
        request = nil
        callback?(value)
    }
}

private final class BrowserLoginResult: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: SourceResponse?
    private var cancelled = false

    var value: SourceResponse? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func finish(_ value: SourceResponse?) {
        lock.lock(); defer { lock.unlock() }
        if !cancelled { stored = value }
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        stored = nil
    }
}
