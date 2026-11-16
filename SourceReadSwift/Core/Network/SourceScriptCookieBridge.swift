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
            let header: String
            switch operation {
            case .read(let url):
                header = await store.cookieHeader(for: url) ?? ""
            case .write(let url, let value):
                await store.storeSetCookieHeaders(["Set-Cookie": value], for: url)
                header = await store.cookieHeader(for: url) ?? ""
            case .remove(let url):
                await store.clearCookies(matching: url)
                await Self.removeBrowserCookies(for: url)
                header = ""
            }
            completion.store(header)
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 10) == .success else {
            task.cancel()
            return nil
        }
        return completion.value
    }

    @MainActor
    private static func removeBrowserCookies(for url: URL) async {
        guard let host = url.host?.lowercased() else { return }
        let webCookies = WKWebsiteDataStore.default().httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            webCookies.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in cookies where matches(cookie, host: host) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                webCookies.delete(cookie) { continuation.resume() }
            }
        }
        for cookie in HTTPCookieStorage.shared.cookies ?? [] where matches(cookie, host: host) {
            HTTPCookieStorage.shared.deleteCookie(cookie)
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
