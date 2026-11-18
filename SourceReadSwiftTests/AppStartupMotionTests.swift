import Combine
import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

@MainActor
final class AppStartupMotionTests: XCTestCase {
    func testWritingServiceIsBoundAndStableOnFirstUse() {
        let app = AppState()
        let server = app.sourceWritingServer
        XCTAssertTrue(server === app.sourceWritingServer)
        XCTAssertTrue(server.sourceStore === app.sourceStore)
        XCTAssertTrue(server.sourceHealthStore === app.sourceHealthStore)
        XCTAssertNotNil(server.engine)
        XCTAssertFalse(server.isRunning)
        XCTAssertFalse(server.isStarting)
    }

    func testReaderSessionDefersGlobalStoreBurstsUntilAfterExit() async {
        let app = AppState()
        await drainMainQueue()
        var changes = 0
        let subscription = app.objectWillChange.sink { changes += 1 }

        app.isReaderPresented = true
        app.sourceStore.objectWillChange.send()
        await drainMainQueue()
        XCTAssertEqual(changes, 1, "Only the reader-presented state may publish while the reader is live")

        changes = 0
        app.sourceStore.objectWillChange.send()
        await drainMainQueue()
        XCTAssertEqual(changes, 0, "Background store bursts must stay out of the live reader tree")

        app.isReaderPresented = false
        await drainMainQueue()
        XCTAssertEqual(changes, 1, "Deferred store state must publish once after the reader leaves")
        withExtendedLifetime(subscription) {}
    }

    func testInjectedArchivesStayIdenticalAndSubscribeOnlyOnFirstAccess() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = RSSArticleStateStore(defaults: defaults)
        let feed = RSSFeedCacheStore(fileURL: directory.appendingPathComponent("feed.json"))
        let content = RSSArticleContentCacheStore(fileURL: directory.appendingPathComponent("content.json"))
        let history = SourceDiagnosticHistoryStore(persistence: SourceDiagnosticHistoryPersistence(rootURL: directory))
        let app = AppState(rssArticleStateStore: state, rssFeedCacheStore: feed,
            rssArticleContentCacheStore: content, sourceDiagnosticHistoryStore: history)
        await drainMainQueue()
        var changes = 0
        let subscription = app.objectWillChange.sink { changes += 1 }

        state.objectWillChange.send()
        feed.objectWillChange.send()
        content.objectWillChange.send()
        history.objectWillChange.send()
        await drainMainQueue()
        XCTAssertEqual(changes, 0, "Unused archives must not install global subscriptions during launch")

        XCTAssertTrue(app.rssArticleStateStore === state)
        XCTAssertTrue(app.rssFeedCacheStore === feed)
        XCTAssertTrue(app.rssArticleContentCacheStore === content)
        XCTAssertTrue(app.sourceDiagnosticHistoryStore === history)
        _ = app.rssFeedCacheStore
        let article = RSSArticlePreview(title: "cached", link: "https://fixture.test/article", pubDate: nil, description: nil)
        state.markRead(article)
        feed.save([article], sourceURL: "https://fixture.test/feed")
        content.save(["正文"], for: article)
        history.objectWillChange.send()
        await drainMainQueue()
        XCTAssertEqual(changes, 1, "First-use stores must retain the existing coalesced root notification")
        XCTAssertTrue(app.rssArticleStateStore.isRead(article))
        XCTAssertEqual(app.rssFeedCacheStore.articles(for: "https://fixture.test/feed")?.count, 1)
        XCTAssertEqual(app.rssArticleContentCacheStore.paragraphs(for: article), ["正文"])
        await feed.waitForPendingWrites()
        await content.waitForPendingWrites()
        try FileManager.default.removeItem(at: directory)
        withExtendedLifetime(subscription) {}
    }

    func testNormalMountedSurfaceDoesNotCreateAnArtificialRefreshDriver() throws {
        let saved = UserDefaults.standard.object(forKey: AppRefreshRateKeeper.diagnosticDefaultsKey)
        defer { UserDefaults.standard.set(saved, forKey: AppRefreshRateKeeper.diagnosticDefaultsKey) }
        UserDefaults.standard.set(false, forKey: AppRefreshRateKeeper.diagnosticDefaultsKey)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: Text("native cadence").highRefreshRateSurface())
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        XCTAssertFalse(containsRefreshDriver(in: host.view))
    }

    func testExplicitLegacyDriverStopsInBackgroundAndDoesNotResumeAutomatically() throws {
        let saved = UserDefaults.standard.object(forKey: AppRefreshRateKeeper.diagnosticDefaultsKey)
        defer { UserDefaults.standard.set(saved, forKey: AppRefreshRateKeeper.diagnosticDefaultsKey) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let driver = AppRefreshRateKeeper()
        host.view.addSubview(driver)
        UserDefaults.standard.set(true, forKey: AppRefreshRateKeeper.diagnosticDefaultsKey)
        driver.start()
        XCTAssertTrue(driver.isHolding)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertFalse(driver.isHolding)
        XCTAssertEqual(driver.heldRate, 0)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppRefreshRateKeeper.diagnosticDefaultsKey))
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        driver.layoutIfNeeded()
        XCTAssertFalse(driver.isHolding)
    }

    func testExplicitLegacyComparisonExpiresEvenWhenKeptMounted() async throws {
        let saved = UserDefaults.standard.object(forKey: AppRefreshRateKeeper.diagnosticDefaultsKey)
        defer { UserDefaults.standard.set(saved, forKey: AppRefreshRateKeeper.diagnosticDefaultsKey) }
        let driver = AppRefreshRateKeeper()
        UserDefaults.standard.set(true, forKey: AppRefreshRateKeeper.diagnosticDefaultsKey)
        driver.start(duration: 0.01)
        for _ in 0..<30 where UserDefaults.standard.bool(forKey: AppRefreshRateKeeper.diagnosticDefaultsKey) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppRefreshRateKeeper.diagnosticDefaultsKey))
        XCTAssertFalse(driver.isHolding)
        driver.layoutIfNeeded()
        XCTAssertFalse(driver.isHolding)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func containsRefreshDriver(in view: UIView) -> Bool {
        view is AppRefreshRateKeeper || view.subviews.contains { containsRefreshDriver(in: $0) }
    }
}
