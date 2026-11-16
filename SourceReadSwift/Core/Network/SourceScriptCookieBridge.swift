import Foundation
import WebKit

/// Uses the engine's cookie jar for synchronous source APIs without blocking the main actor.
final class SourceScriptCookieBridge: @unchecked Sendable {
    enum Operation: Sendable {
        case read(URL)
        case write(URL, String)
        case remove(URL)
    }

    private let store: SourceCookieStore

    init(store: SourceCookieStore) { self.store = store }

    func perform(_ operation: Operation) -> String? {
        guard !Thread.isMainThread else { return nil }
        let completion = CookieResult()
        let semaphore = DispatchSemaphore(value: 0)
        let task = Task.detached { [store] in
            defer { semaphore.signal() }
            let header: String
            switch operation {
            case .read(let url):
                header = await store.cookieHeader(for: url) ?? ""
            case .write(let url, let value):
                await store.storeSetCookieHeaders(["Set-Cookie": value], for: url)
                guard await store.persistenceFailure == nil else { return }
                header = await store.cookieHeader(for: url) ?? ""
            case .remove(let url):
                await store.clearCookies(matching: url)
                let failure = await store.persistenceFailure
                await Self.removeBrowserCookies(for: url)
                guard failure == nil else { return }
                header = ""
            }
            completion.store(header)
        }
        guard semaphore.wait(timeout: .now() + 10) == .success else {
            task.cancel()
            return nil
        }
        return completion.value
    }

    /// Clears the settings page's selected domain bucket (or all buckets) from every Cookie container.
    @MainActor
    static func clearCookies(in store: SourceCookieStore, host: String? = nil,
                             webCookies: WKHTTPCookieStore? = nil, sharedCookies: HTTPCookieStorage = .shared) async throws {
        let normalized = host?.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
        if let normalized { await store.clearCookies(for: normalized) }
        else { await store.clearAllCookies() }
        let failure = await store.persistenceFailure
        await removeBrowserCookies(where: { cookie in
            guard let normalized else { return true }
            return cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased() == normalized
        }, webCookies: webCookies, sharedCookies: sharedCookies)
        if let failure { throw failure }
    }

    @MainActor
    private static func removeBrowserCookies(for url: URL) async {
        guard let host = url.host?.lowercased() else { return }
        await removeBrowserCookies(where: { matches($0, host: host) })
    }

    @MainActor
    private static func removeBrowserCookies(where shouldRemove: (HTTPCookie) -> Bool,
                                             webCookies: WKHTTPCookieStore? = nil,
                                             sharedCookies: HTTPCookieStorage = .shared) async {
        let webCookies = webCookies ?? WKWebsiteDataStore.default().httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            webCookies.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in cookies where shouldRemove(cookie) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                webCookies.delete(cookie) { continuation.resume() }
            }
        }
        for cookie in sharedCookies.cookies ?? [] where shouldRemove(cookie) {
            sharedCookies.deleteCookie(cookie)
        }
    }

    private static func matches(_ cookie: HTTPCookie, host: String) -> Bool {
        let domain = cookie.domain.lowercased()
        guard domain.hasPrefix(".") else { return host == domain }
        let bare = String(domain.dropFirst())
        return host == bare || host.hasSuffix("." + bare)
    }
}

private final class CookieResult: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    var value: String? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
    func store(_ header: String) {
        lock.lock(); stored = header; lock.unlock()
    }
}
