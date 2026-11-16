import XCTest
import WebKit
@testable import SourceReadSwift

final class SourceBrowserCookieSnapshotTests: XCTestCase {
    @MainActor
    func testBrowserCompletionRejectsFailedCookiePersistence() async throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("blocked".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let store = SourceCookieStore(storageURL: blocker.appendingPathComponent("cookies.json"))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let browser = WKWebView(frame: .zero, configuration: configuration)
        let session = try cookie("session", domain: "write.snapshot.invalid")
        defer { HTTPCookieStorage.shared.deleteCookie(session) }
        await set(session, in: configuration.websiteDataStore.httpCookieStore)
        let scope = SourceLoginCookieScope()
        scope.recordVisit(to: URL(string: "https://write.snapshot.invalid/"))

        do {
            _ = try await SourceLoginBrowserCookies.synchronizePersistently(from: browser, into: store, scope: scope)
            XCTFail("The browser must stay open when its Cookie could not be saved")
        } catch let failure as SourceCookieStore.PersistenceFailure {
            XCTAssertEqual(failure.operation, .write)
        }
        let active = await store.cookieCount()
        XCTAssertEqual(active, 1, "The current session remains usable while saving is retried")
    }

    @MainActor
    func testCookieManagerHostClearCannotBeReimportedFromBrowserAndPreservesOtherBuckets() async throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: location) }
        let store = SourceCookieStore(storageURL: location)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webCookies = configuration.websiteDataStore.httpCookieStore
        let nativeCookies = try XCTUnwrap(URLSessionConfiguration.ephemeral.httpCookieStorage)
        let selected = try cookie("selected", domain: "clear.snapshot.invalid", path: "/account")
        let parent = try cookie("parent", domain: ".snapshot.invalid")
        let sibling = try cookie("sibling", domain: "other.snapshot.invalid")
        for value in [selected, parent, sibling] {
            await set(value, in: webCookies)
            nativeCookies.setCookie(value)
        }
        await store.storeWebViewCookies([selected, parent, sibling])

        try await SourceScriptCookieBridge.clearCookies(in: store, host: "clear.snapshot.invalid",
            webCookies: webCookies, sharedCookies: nativeCookies)
        let browserRemaining = await allCookies(in: webCookies)
        XCTAssertEqual(Set(browserRemaining.map(\.name)), ["parent", "sibling"])
        XCTAssertEqual(Set((nativeCookies.cookies ?? []).map(\.name)), ["parent", "sibling"])
        await store.replaceWebViewCookies(browserRemaining, forVisitedHosts: ["clear.snapshot.invalid"])
        let restored = await SourceCookieStore(storageURL: location).allCookies()
        XCTAssertEqual(Set(restored.map(\.name)), ["parent", "sibling"])
    }

    @MainActor
    func testCookieManagerClearAllCannotBeReimportedAfterRelaunch() async throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: location) }
        let store = SourceCookieStore(storageURL: location)
        let webCookies = WKWebsiteDataStore.nonPersistent().httpCookieStore
        let nativeCookies = try XCTUnwrap(URLSessionConfiguration.ephemeral.httpCookieStorage)
        let session = try cookie("session", domain: "clear-all.snapshot.invalid")
        await store.storeWebViewCookies([session])
        await set(session, in: webCookies)
        nativeCookies.setCookie(session)

        try await SourceScriptCookieBridge.clearCookies(in: store,
            webCookies: webCookies, sharedCookies: nativeCookies)
        let remaining = await allCookies(in: webCookies)
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue((nativeCookies.cookies ?? []).isEmpty)
        await store.replaceWebViewCookies(remaining, forVisitedHosts: ["clear-all.snapshot.invalid"])
        let restored = await SourceCookieStore(storageURL: location).cookieCount()
        XCTAssertEqual(restored, 0)
    }

    @MainActor
    func testCookieManagerClearAllRemovesEveryContainerAndSurfacesSaveFailure() async throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("blocked".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let store = SourceCookieStore(storageURL: blocker.appendingPathComponent("cookies.json"))
        let webCookies = WKWebsiteDataStore.nonPersistent().httpCookieStore
        let nativeCookies = try XCTUnwrap(URLSessionConfiguration.ephemeral.httpCookieStorage)
        let session = try cookie("session", domain: "clear-all.snapshot.invalid")
        await store.storeWebViewCookies([session])
        await set(session, in: webCookies)
        nativeCookies.setCookie(session)

        do {
            try await SourceScriptCookieBridge.clearCookies(in: store,
                webCookies: webCookies, sharedCookies: nativeCookies)
            XCTFail("A failed durable logout must not be reported as complete")
        } catch let failure as SourceCookieStore.PersistenceFailure {
            XCTAssertEqual(failure.operation, .write)
        }
        let remaining = await allCookies(in: webCookies)
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue((nativeCookies.cookies ?? []).isEmpty)
        let active = await store.cookieCount()
        XCTAssertEqual(active, 0)
    }

    @MainActor
    func testDeletedWebKitCookieCannotReturnFromNativeStoreAfterRelaunch() async throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: location) }
        let store = SourceCookieStore(storageURL: location)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let browser = WKWebView(frame: .zero, configuration: configuration)
        let origin = URL(string: "https://logout.snapshot.invalid/account")!
        let session = try cookie("session", domain: "logout.snapshot.invalid")
        defer { HTTPCookieStorage.shared.deleteCookie(session) }
        await store.store([session], for: origin)
        await set(session, in: configuration.websiteDataStore.httpCookieStore)
        let scope = SourceLoginCookieScope()
        scope.recordVisit(to: origin)
        let initialCount = await SourceLoginBrowserCookies.synchronize(from: browser, into: store, scope: scope)
        XCTAssertEqual(initialCount, 1)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            configuration.websiteDataStore.httpCookieStore.delete(session) { continuation.resume() }
        }
        let remaining = await SourceLoginBrowserCookies.synchronize(from: browser, into: store, scope: scope)
        let activeHeader = await store.cookieHeader(for: origin)
        let restoredHeader = await SourceCookieStore(storageURL: location).cookieHeader(for: origin)
        XCTAssertEqual(remaining, 0)
        XCTAssertNil(activeHeader, "A cookie removed by web logout must also disappear from the actor")
        XCTAssertNil(restoredHeader, "Reopening the app must not inject the deleted cookie again")
        XCTAssertFalse((HTTPCookieStorage.shared.cookies(for: origin) ?? []).contains { $0.name == session.name })
    }

    func testSnapshotDeletionIncludesParentDomainButPreservesHostOnlySiblingAndUnrelatedSites() async throws {
        let store = SourceCookieStore(storageURL: nil)
        let parent = try cookie("parent", domain: ".snapshot.invalid")
        let login = try cookie("login", domain: "login.snapshot.invalid", path: "/account")
        let sibling = try cookie("sibling", domain: "api.snapshot.invalid")
        let unrelated = try cookie("other", domain: "othersnapshot.invalid")
        await store.storeWebViewCookies([parent, login, sibling, unrelated])

        await store.replaceWebViewCookies([], forVisitedHosts: ["login.snapshot.invalid"])
        let remaining = await store.allCookies()
        XCTAssertEqual(Set(remaining.map(\.name)), ["sibling", "other"])
    }

    func testSnapshotReplacesOnlyVisitedDomainsAndHonorsCookiePathIdentity() async throws {
        let store = SourceCookieStore(storageURL: nil)
        let root = try cookie("session", domain: "login.snapshot.invalid")
        let account = try cookie("session", domain: "login.snapshot.invalid", path: "/account")
        let unrelated = try cookie("unrelated", domain: "separate.invalid")
        await store.storeWebViewCookies([root, account, unrelated])
        let refreshed = try cookie("session", domain: "login.snapshot.invalid", path: "/account", value: "refreshed")
        let browserOnly = try cookie("browser-only", domain: "outside.invalid")
        await store.replaceWebViewCookies([refreshed, browserOnly], forVisitedHosts: ["login.snapshot.invalid"])

        let remaining = await store.allCookies()
        XCTAssertEqual(remaining.count, 2)
        let restored = try XCTUnwrap(remaining.first { $0.name == "session" })
        XCTAssertEqual(restored.path, "/account")
        XCTAssertEqual(restored.value, "refreshed")
        XCTAssertTrue(remaining.contains { $0.name == "unrelated" })
        XCTAssertFalse(remaining.contains { $0.name == "browser-only" })
    }

    @MainActor
    func testRedirectScopeRemembersLoginHostAfterArrivingAtDifferentHost() async throws {
        let store = SourceCookieStore(storageURL: nil)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let browser = WKWebView(frame: .zero, configuration: configuration)
        let login = try cookie("oauth", domain: "login.snapshot.invalid")
        let unrelated = try cookie("unrelated", domain: "untouched.invalid")
        let final = try cookie("session", domain: "reader.snapshot.invalid")
        defer { HTTPCookieStorage.shared.deleteCookie(final) }
        await store.storeWebViewCookies([login, unrelated])
        await set(final, in: configuration.websiteDataStore.httpCookieStore)
        let scope = SourceLoginCookieScope()
        scope.recordVisit(to: URL(string: "https://login.snapshot.invalid/sign-in"))
        scope.recordVisit(to: URL(string: "https://reader.snapshot.invalid/callback"))

        let count = await SourceLoginBrowserCookies.synchronize(from: browser, into: store, scope: scope)
        let remaining = await store.allCookies()
        XCTAssertEqual(count, 1)
        XCTAssertEqual(Set(remaining.map(\.name)), ["unrelated", "session"])
    }

    func testEmptyScopeCannotEraseOrImportCookiesFromUnrelatedBrowserTabs() async throws {
        let store = SourceCookieStore(storageURL: nil)
        let existing = try cookie("existing", domain: "untouched.invalid")
        let foreign = try cookie("foreign", domain: "outside.invalid")
        await store.storeWebViewCookies([existing])
        await store.replaceWebViewCookies([foreign], forVisitedHosts: [])
        let remaining = await store.allCookies()
        XCTAssertEqual(remaining.map(\.name), ["existing"])
    }

    private func cookie(_ name: String, domain: String, path: String = "/", value: String = "fixture") throws -> HTTPCookie {
        try XCTUnwrap(HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: path]))
    }

    @MainActor
    private func allCookies(in store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
    }

    @MainActor
    private func set(_ cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.setCookie(cookie) { continuation.resume() }
        }
    }
}
