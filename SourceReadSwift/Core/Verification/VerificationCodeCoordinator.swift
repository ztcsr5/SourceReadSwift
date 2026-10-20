import Foundation
import Combine

/// A verification-code challenge raised by a Legado source while a rule is
/// executing.  `imageURL` is already resolved against the source base URL and
/// `cookieHeader` carries the source-scoped cookies required by most captcha
/// endpoints.
struct VerificationCodeRequest: Identifiable, Equatable {
    let id: UUID
    let imageURL: String
    let sourceName: String
    let stage: String
    let cookieHeader: String

    init(
        id: UUID = UUID(),
        imageURL: String,
        sourceName: String,
        stage: String,
        cookieHeader: String
    ) {
        self.id = id
        self.imageURL = imageURL
        self.sourceName = sourceName
        self.stage = stage
        self.cookieHeader = cookieHeader
    }
}

/// Single source of truth for captcha URL resolution.  The JavaScript bridge,
/// the cache key, and the image loader must all agree on the absolute URL;
/// otherwise a relative path and its absolute form become two challenges.
enum VerificationCodeURLResolver {
    static func resolve(imageURL: String, baseURL: String) -> String {
        let trimmed = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return trimmed
        }
        guard let base = URL(string: baseURL), let resolved = URL(string: trimmed, relativeTo: base) else {
            return trimmed
        }
        return resolved.absoluteString
    }
}

/// Bridges the synchronous JavaScriptCore `java.getVerificationCode` call to a
/// SwiftUI sheet.  The JavaScript bridge runs on a cooperative-pool thread, so
/// it can wait on a semaphore while the main actor presents the prompt.  If the
/// caller is already on the main thread the request is rejected immediately to
/// avoid a deadlock; that case is recorded as a bridge failure by the caller.
@MainActor
final class VerificationCodeCoordinator: ObservableObject {
    static let shared = VerificationCodeCoordinator()

    @Published var request: VerificationCodeRequest?

    private var completion: ((String) -> Void)?

    private init() {}

    /// Nonisolated entry point used by the JavaScript host bridge.
    ///
    /// The wait polls instead of blocking for the whole timeout so a cancelled
    /// source pipeline (for example `AsyncTimeout`) releases its cooperative
    /// thread promptly and closes the stale prompt.
    ///
    /// - Returns: the submitted code, or an empty string on timeout/cancel.
    nonisolated static func requestSynchronously(
        imageURL: String,
        sourceName: String,
        stage: String,
        baseURL: String,
        cookieHeader: String,
        timeout: TimeInterval = 180
    ) -> String {
        guard !Thread.isMainThread else { return "" }

        let resolvedURL = VerificationCodeURLResolver.resolve(imageURL: imageURL, baseURL: baseURL)
        guard !resolvedURL.isEmpty else { return "" }

        let request = VerificationCodeRequest(
            imageURL: resolvedURL,
            sourceName: sourceName,
            stage: stage,
            cookieHeader: cookieHeader
        )
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)

        Task { @MainActor in
            guard !box.isCancelled else { return }
            shared.present(request) { value in
                box.set(value)
                semaphore.signal()
            }
        }

        let deadline = Date().addingTimeInterval(max(timeout, 0.05))
        while true {
            if semaphore.wait(timeout: .now() + 0.25) == .success {
                return box.value
            }
            if Task.isCancelled || Date() >= deadline {
                box.cancel()
                Task { @MainActor in shared.cancel(id: request.id) }
                return ""
            }
        }
    }

    func present(_ request: VerificationCodeRequest, completion: @escaping (String) -> Void) {
        // A second challenge while the first is still open supersedes it.
        if self.request != nil {
            finish(with: "")
        }
        self.request = request
        self.completion = completion
    }

    func submit(id: UUID, code: String) {
        guard request?.id == id else { return }
        finish(with: code.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func cancel(id: UUID) {
        guard request?.id == id else { return }
        finish(with: "")
    }

    private func finish(with value: String) {
        let callback = completion
        completion = nil
        request = nil
        callback?(value)
    }
}

/// Small thread-safe box because the completion fires on the main actor while
/// the JavaScript bridge thread reads the value after `wait` returns.
private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = ""
    private var cancelled = false

    var value: String {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    func set(_ value: String) {
        lock.lock()
        if !cancelled { stored = value }
        lock.unlock()
    }
}
